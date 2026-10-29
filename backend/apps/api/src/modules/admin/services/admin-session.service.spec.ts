import {
  ADMIN_SESSION_IDLE_MS,
  ADMIN_SESSION_TOUCH_INTERVAL_MS,
} from '../auth/admin-auth.policy';
import {
  AdminSessionService,
  decideSessionState,
  type AdminSessionRow,
} from './admin-session.service';

describe('admin sessions', () => {
  const now = new Date('2026-10-28T10:00:00Z');
  const row = (over: Partial<AdminSessionRow> = {}): AdminSessionRow => ({
    id: 'sess-1',
    adminAccountId: 'acct-1',
    lastSeenAt: new Date(now.getTime() - 60_000),
    expiresAt: new Date(now.getTime() + 3_600_000),
    mfaVerifiedAt: new Date(now.getTime() - 60_000),
    revokedAt: null,
    ...over,
  });

  describe('decideSessionState', () => {
    it('accepts a live session of the same admin', () => {
      expect(decideSessionState(row(), 'acct-1', now)).toEqual({
        ok: true,
        session: row(),
      });
    });

    it("treats a missing session, or another admin's, as unknown", () => {
      expect(decideSessionState(null, 'acct-1', now)).toEqual({
        ok: false,
        reason: 'UNKNOWN',
      });
      expect(decideSessionState(row(), 'acct-2', now)).toEqual({
        ok: false,
        reason: 'UNKNOWN',
      });
    });

    it('refuses revoked, expired and idle sessions', () => {
      expect(
        decideSessionState(row({ revokedAt: now }), 'acct-1', now),
      ).toMatchObject({ reason: 'REVOKED' });
      expect(
        decideSessionState(row({ expiresAt: now }), 'acct-1', now),
      ).toMatchObject({ reason: 'EXPIRED' });
      expect(
        decideSessionState(
          row({
            lastSeenAt: new Date(now.getTime() - ADMIN_SESSION_IDLE_MS - 1),
          }),
          'acct-1',
          now,
        ),
      ).toMatchObject({ reason: 'IDLE' });
    });
  });

  describe('create', () => {
    it('returns the token once and stores only its hash', async () => {
      const create = jest
        .fn<Promise<{ id: string }>, [{ data: Record<string, unknown> }]>()
        .mockResolvedValue({ id: 'sess-9' });
      const service = new AdminSessionService({} as never);
      const issued = await service.create(
        { adminSession: { create } } as never,
        'acct-1',
        { requestId: 'req-1', ipAddress: '203.0.113.9', userAgent: 'ua' },
        now,
      );
      const data = create.mock.calls[0][0].data;
      expect(issued.sessionId).toBe('sess-9');
      expect(data.tokenHash).toMatch(/^[0-9a-f]{64}$/);
      expect(JSON.stringify(data)).not.toContain(issued.sessionToken);
      expect(data.mfaVerifiedAt).toEqual(now);
      expect(issued.expiresAt.getTime() - now.getTime()).toBe(12 * 3600_000);
    });
  });

  describe('touch', () => {
    it('writes lastSeenAt at most once per interval, never on a revoked session', async () => {
      const updateMany = jest.fn().mockResolvedValue({ count: 1 });
      const service = new AdminSessionService({
        adminSession: { updateMany },
      } as never);

      await service.touch(
        row({ lastSeenAt: new Date(now.getTime() - 1_000) }),
        now,
      );
      expect(updateMany).not.toHaveBeenCalled();

      await service.touch(
        row({
          lastSeenAt: new Date(now.getTime() - ADMIN_SESSION_TOUCH_INTERVAL_MS),
        }),
        now,
      );
      expect(updateMany).toHaveBeenCalledWith({
        where: { id: 'sess-1', revokedAt: null },
        data: { lastSeenAt: now },
      });
    });
  });
});
