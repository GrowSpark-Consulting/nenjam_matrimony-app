import { AttributionInput, decideAttribution } from './decide-attribution';

const NOW = new Date('2026-10-27T10:00:00.000Z');

const valid = (
  overrides: Partial<AttributionInput> = {},
): AttributionInput => ({
  source: 'CODE_AT_SIGNUP',
  codeFound: true,
  codeActive: true,
  agentStatus: 'ACTIVE',
  memberPhoneHash: 'member-hash',
  agentPhoneHash: 'agent-hash',
  memberAlreadyAttributed: false,
  phoneAlreadyCredited: false,
  memberHasPaid: false,
  now: NOW,
  creditWindowDays: 60,
  ...overrides,
});

describe('decideAttribution', () => {
  describe('success', () => {
    it('credits a signup code and ends the window creditWindowDays later', () => {
      const result = decideAttribution(valid());
      expect(result).toEqual({
        ok: true,
        windowEndsAt: new Date('2026-12-26T10:00:00.000Z'),
      });
    });

    it('uses the window it is given, not a built-in one', () => {
      const result = decideAttribution(valid({ creditWindowDays: 7 }));
      expect(result).toEqual({
        ok: true,
        windowEndsAt: new Date('2026-11-03T10:00:00.000Z'),
      });
    });

    it('works for LINK_OR_QR the same way', () => {
      const result = decideAttribution(valid({ source: 'LINK_OR_QR' }));
      expect(result).toEqual({
        ok: true,
        windowEndsAt: new Date('2026-12-26T10:00:00.000Z'),
      });
    });

    it('allows a zero-day window (ends now)', () => {
      const result = decideAttribution(valid({ creditWindowDays: 0 }));
      expect(result).toEqual({ ok: true, windowEndsAt: NOW });
    });

    it('does not mutate or alias the input date', () => {
      const result = decideAttribution(valid({ creditWindowDays: 0 }));
      expect(result.ok && result.windowEndsAt).not.toBe(NOW);
      expect(NOW.toISOString()).toBe('2026-10-27T10:00:00.000Z');
    });

    it('has no needsReview or markRejected on a plain success', () => {
      const result = decideAttribution(valid());
      expect(result).not.toHaveProperty('needsReview');
      expect(result).not.toHaveProperty('markRejected');
    });
  });

  describe('ENTERED_AT_PAYMENT', () => {
    it('ends the window at now, whatever creditWindowDays is', () => {
      const result = decideAttribution(
        valid({ source: 'ENTERED_AT_PAYMENT', creditWindowDays: 60 }),
      );
      expect(result).toEqual({ ok: true, windowEndsAt: NOW });
    });

    it('is still refused after an earlier paid plan', () => {
      expect(
        decideAttribution(
          valid({ source: 'ENTERED_AT_PAYMENT', memberHasPaid: true }),
        ),
      ).toEqual({ ok: false, reason: 'ALREADY_PAID' });
    });
  });

  describe('each rejection reason', () => {
    it('INVALID_CODE when the code was not found', () => {
      expect(decideAttribution(valid({ codeFound: false }))).toEqual({
        ok: false,
        reason: 'INVALID_CODE',
      });
    });

    it('CODE_INACTIVE when the code is switched off', () => {
      expect(decideAttribution(valid({ codeActive: false }))).toEqual({
        ok: false,
        reason: 'CODE_INACTIVE',
      });
    });

    it.each([
      'PENDING_APPROVAL',
      'REJECTED',
      'SUSPENDED',
      'TERMINATED',
      'anything-else',
    ])('AGENT_NOT_ACTIVE when the agent is %s', (agentStatus) => {
      expect(decideAttribution(valid({ agentStatus }))).toEqual({
        ok: false,
        reason: 'AGENT_NOT_ACTIVE',
      });
    });

    it('SELF_REFERRAL when both phone hashes match, and marks it rejected', () => {
      expect(
        decideAttribution(
          valid({ memberPhoneHash: 'same', agentPhoneHash: 'same' }),
        ),
      ).toEqual({ ok: false, reason: 'SELF_REFERRAL', markRejected: true });
    });

    it('is not a self-referral when only one hash is known', () => {
      expect(decideAttribution(valid({ agentPhoneHash: null })).ok).toBe(true);
    });

    it('does not treat two missing hashes as equal', () => {
      const result = decideAttribution(
        valid({
          source: 'ENTERED_AT_PAYMENT',
          memberPhoneHash: null,
          agentPhoneHash: null,
        }),
      );
      expect(result).toEqual({
        ok: true,
        windowEndsAt: NOW,
        needsReview: true,
      });
    });

    it('ALREADY_ATTRIBUTED when the member already has an agent', () => {
      expect(
        decideAttribution(valid({ memberAlreadyAttributed: true })),
      ).toEqual({ ok: false, reason: 'ALREADY_ATTRIBUTED' });
    });

    it('PHONE_ALREADY_CREDITED when the phone was credited before', () => {
      expect(decideAttribution(valid({ phoneAlreadyCredited: true }))).toEqual({
        ok: false,
        reason: 'PHONE_ALREADY_CREDITED',
      });
    });

    it.each(['CODE_AT_SIGNUP', 'LINK_OR_QR', 'ENTERED_AT_PAYMENT'] as const)(
      'ALREADY_PAID for source %s',
      (source) => {
        expect(
          decideAttribution(valid({ source, memberHasPaid: true })),
        ).toEqual({ ok: false, reason: 'ALREADY_PAID' });
      },
    );
  });

  describe('missing member phone hash (pending decision)', () => {
    it.each(['CODE_AT_SIGNUP', 'LINK_OR_QR'] as const)(
      '%s is refused with PHONE_NOT_VERIFIED',
      (source) => {
        expect(
          decideAttribution(valid({ source, memberPhoneHash: null })),
        ).toEqual({ ok: false, reason: 'PHONE_NOT_VERIFIED' });
      },
    );

    it('ENTERED_AT_PAYMENT is accepted but flagged needsReview', () => {
      expect(
        decideAttribution(
          valid({ source: 'ENTERED_AT_PAYMENT', memberPhoneHash: null }),
        ),
      ).toEqual({ ok: true, windowEndsAt: NOW, needsReview: true });
    });
  });

  describe('order of checks', () => {
    // One way to break each rule, in the order they are checked.
    const breakers: Array<[string, Partial<AttributionInput>]> = [
      ['INVALID_CODE', { codeFound: false }],
      ['CODE_INACTIVE', { codeActive: false }],
      ['AGENT_NOT_ACTIVE', { agentStatus: 'SUSPENDED' }],
      ['SELF_REFERRAL', { memberPhoneHash: 'same', agentPhoneHash: 'same' }],
      ['ALREADY_ATTRIBUTED', { memberAlreadyAttributed: true }],
      ['PHONE_ALREADY_CREDITED', { phoneAlreadyCredited: true }],
      ['ALREADY_PAID', { memberHasPaid: true }],
      ['PHONE_NOT_VERIFIED', { memberPhoneHash: null }],
    ];

    for (let i = 0; i < breakers.length; i++) {
      for (let j = i + 1; j < breakers.length; j++) {
        // A missing member hash cannot also be a self-referral.
        if (
          breakers[i][0] === 'SELF_REFERRAL' &&
          breakers[j][0] === 'PHONE_NOT_VERIFIED'
        ) {
          continue;
        }
        it(`${breakers[i][0]} wins over ${breakers[j][0]}`, () => {
          const result = decideAttribution(
            valid({ ...breakers[i][1], ...breakers[j][1] }),
          );
          expect(result).toMatchObject({ ok: false, reason: breakers[i][0] });
        });
      }
    }

    it('everything wrong at once reports INVALID_CODE', () => {
      const result = decideAttribution(
        valid({
          codeFound: false,
          codeActive: false,
          agentStatus: 'TERMINATED',
          memberAlreadyAttributed: true,
          phoneAlreadyCredited: true,
          memberHasPaid: true,
          memberPhoneHash: null,
        }),
      );
      expect(result).toEqual({ ok: false, reason: 'INVALID_CODE' });
    });

    it('the first agent stays even if the phone is also self-matching later', () => {
      // memberAlreadyAttributed is checked after self-referral, before credit.
      expect(
        decideAttribution(
          valid({ memberAlreadyAttributed: true, memberHasPaid: true }),
        ),
      ).toEqual({ ok: false, reason: 'ALREADY_ATTRIBUTED' });
    });
  });

  describe('invalid settings and inputs', () => {
    it.each([-1, 1.5, NaN, Infinity])('rejects creditWindowDays %p', (days) => {
      expect(() =>
        decideAttribution(valid({ creditWindowDays: days })),
      ).toThrow(RangeError);
    });

    it('validates creditWindowDays before any other check', () => {
      expect(() =>
        decideAttribution(valid({ codeFound: false, creditWindowDays: -1 })),
      ).toThrow(RangeError);
    });

    it('rejects an invalid now', () => {
      expect(() => decideAttribution(valid({ now: new Date('nope') }))).toThrow(
        RangeError,
      );
    });
  });
});
