import {
  clientDraftExpiresAt,
  decideClientAccept,
  decideClientDraftCreate,
  decideClientDraftSubmit,
  effectiveClientDraftStatus,
  type ClientAcceptInput,
} from './decide-client-draft';

const NOW = new Date('2026-11-03T10:00:00.000Z');
const DAY = 86_400_000;

const FINE = {
  canReach: true,
  phoneIsMember: false,
  phoneCredited: false,
  isAgentsOwnPhone: false,
  rejectedBefore: false,
};
const CREATE = {
  ...FINE,
  hasOpenDraftForPhone: false,
  openCount: 3,
  draftLimit: 10,
};

describe('decideClientDraftCreate', () => {
  it('allows a reachable, unused phone under the limit', () => {
    expect(decideClientDraftCreate(CREATE)).toEqual({ ok: true });
  });

  it('refuses a phone no code can reach before anything else is judged', () => {
    expect(
      decideClientDraftCreate({
        ...CREATE,
        canReach: false,
        hasOpenDraftForPhone: true,
        openCount: 10,
        phoneIsMember: true,
      }),
    ).toEqual({ ok: false, reason: 'DELIVERY_UNAVAILABLE' });
  });

  it('an open draft for the phone, then the limit', () => {
    expect(
      decideClientDraftCreate({
        ...CREATE,
        hasOpenDraftForPhone: true,
        openCount: 10,
      }),
    ).toEqual({ ok: false, reason: 'DRAFT_EXISTS' });
    expect(decideClientDraftCreate({ ...CREATE, openCount: 10 })).toEqual({
      ok: false,
      reason: 'LIMIT_REACHED',
    });
    expect(decideClientDraftCreate({ ...CREATE, openCount: 9 })).toEqual({
      ok: true,
    });
    expect(
      decideClientDraftCreate({ ...CREATE, draftLimit: 0, openCount: 0 }),
    ).toEqual({
      ok: false,
      reason: 'LIMIT_REACHED',
    });
  });

  it('every phone reason is the same refusal, with the internal reason kept', () => {
    const cases = [
      [{ isAgentsOwnPhone: true }, 'OWN_PHONE'],
      [{ rejectedBefore: true }, 'REJECTED_BEFORE'],
      [{ phoneIsMember: true }, 'MEMBER'],
      [{ phoneCredited: true }, 'CREDITED'],
    ] as const;
    for (const [facts, refusal] of cases) {
      expect(decideClientDraftCreate({ ...CREATE, ...facts })).toEqual({
        ok: false,
        reason: 'PHONE_UNAVAILABLE',
        refusal,
      });
    }
  });

  it('refuses a bad limit (a programming error)', () => {
    expect(() =>
      decideClientDraftCreate({ ...CREATE, draftLimit: -1 }),
    ).toThrow(RangeError);
    expect(() =>
      decideClientDraftCreate({ ...CREATE, draftLimit: 1.5 }),
    ).toThrow(RangeError);
  });
});

describe('decideClientDraftSubmit', () => {
  it('checks reach and the phone again, but not the limit', () => {
    expect(decideClientDraftSubmit(FINE)).toEqual({ ok: true });
    expect(decideClientDraftSubmit({ ...FINE, canReach: false })).toEqual({
      ok: false,
      reason: 'DELIVERY_UNAVAILABLE',
    });
    expect(decideClientDraftSubmit({ ...FINE, phoneIsMember: true })).toEqual({
      ok: false,
      reason: 'PHONE_UNAVAILABLE',
      refusal: 'MEMBER',
    });
  });
});

describe('clientDraftExpiresAt / effectiveClientDraftStatus', () => {
  it('counts whole days from the given moment', () => {
    expect(clientDraftExpiresAt(NOW, 14)).toEqual(
      new Date(NOW.getTime() + 14 * DAY),
    );
    expect(() => clientDraftExpiresAt(NOW, 0)).toThrow(RangeError);
  });

  it('an open draft is EXPIRED from the very moment it runs out', () => {
    const expiresAt = new Date(NOW.getTime() + 1000);
    for (const status of ['DRAFT', 'WAITING_FOR_CLIENT'] as const) {
      expect(effectiveClientDraftStatus({ status, expiresAt }, NOW)).toBe(
        status,
      );
      expect(effectiveClientDraftStatus({ status, expiresAt }, expiresAt)).toBe(
        'EXPIRED',
      );
    }
  });

  it('a closed draft keeps its own status', () => {
    const past = new Date(NOW.getTime() - DAY);
    for (const status of ['ACCEPTED', 'REJECTED', 'EXPIRED'] as const) {
      expect(effectiveClientDraftStatus({ status, expiresAt: past }, NOW)).toBe(
        status,
      );
    }
  });
});

describe('decideClientAccept', () => {
  const OPEN: ClientAcceptInput = {
    status: 'WAITING_FOR_CLIENT',
    expiresAt: new Date(NOW.getTime() + DAY),
    now: NOW,
    agentStatus: 'ACTIVE',
    acceptedMemberExists: false,
    phoneIsMember: false,
    phoneCredited: false,
    creditWindowDays: 60,
  };

  it('accepts and credits for the credit window from now', () => {
    expect(decideClientAccept(OPEN)).toEqual({
      kind: 'ACCEPT',
      windowEndsAt: new Date(NOW.getTime() + 60 * DAY),
    });
  });

  it('judges the expiry itself, to the millisecond', () => {
    expect(decideClientAccept({ ...OPEN, expiresAt: NOW })).toEqual({
      kind: 'REFUSE',
      reason: 'UNAVAILABLE',
    });
    expect(
      decideClientAccept({ ...OPEN, expiresAt: new Date(NOW.getTime() + 1) })
        .kind,
    ).toBe('ACCEPT');
  });

  it('refuses a draft that is not waiting, and an agent that is not active', () => {
    for (const status of ['DRAFT', 'REJECTED', 'EXPIRED'] as const) {
      expect(decideClientAccept({ ...OPEN, status })).toEqual({
        kind: 'REFUSE',
        reason: 'UNAVAILABLE',
      });
    }
    for (const agentStatus of ['SUSPENDED', 'TERMINATED', '']) {
      expect(decideClientAccept({ ...OPEN, agentStatus })).toEqual({
        kind: 'REFUSE',
        reason: 'UNAVAILABLE',
      });
    }
  });

  it('a phone that is (or was) a member is sent to sign in', () => {
    for (const facts of [{ phoneIsMember: true }, { phoneCredited: true }]) {
      expect(decideClientAccept({ ...OPEN, ...facts })).toEqual({
        kind: 'REFUSE',
        reason: 'ALREADY_MEMBER',
      });
    }
  });

  it('an accepted draft is a repeat while its member exists, whatever the clock says', () => {
    const accepted = { ...OPEN, status: 'ACCEPTED' as const, expiresAt: NOW };
    expect(
      decideClientAccept({ ...accepted, acceptedMemberExists: true }),
    ).toEqual({
      kind: 'REPEAT',
    });
    expect(decideClientAccept(accepted)).toEqual({
      kind: 'REFUSE',
      reason: 'UNAVAILABLE',
    });
  });

  it('refuses a bad window (a programming error)', () => {
    expect(() => decideClientAccept({ ...OPEN, creditWindowDays: -1 })).toThrow(
      RangeError,
    );
  });
});
