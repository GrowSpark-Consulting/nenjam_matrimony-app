import {
  ApplicationSubmitInput,
  decideApplicationSubmit,
} from './decide-application-submit';

const input = (
  overrides: Partial<ApplicationSubmitInput> = {},
): ApplicationSubmitInput => ({
  tokenScope: 'APPLICANT',
  existingAgentStatus: null,
  rejectedMayReapply: true,
  phoneAlreadyHasAgent: false,
  ...overrides,
});

describe('decideApplicationSubmit', () => {
  describe('no agent record', () => {
    it('an applicant creates a PENDING_APPROVAL agent', () => {
      expect(decideApplicationSubmit(input())).toEqual({
        allowed: true,
        action: 'CREATE_PENDING',
      });
    });

    it('PHONE_ALREADY_REGISTERED when the phone already has an agent', () => {
      expect(
        decideApplicationSubmit(input({ phoneAlreadyHasAgent: true })),
      ).toEqual({ allowed: false, reason: 'PHONE_ALREADY_REGISTERED' });
    });

    it('SCOPE_MISMATCH for an AGENT token with no agent record', () => {
      expect(decideApplicationSubmit(input({ tokenScope: 'AGENT' }))).toEqual({
        allowed: false,
        reason: 'SCOPE_MISMATCH',
      });
    });

    it('PHONE_ALREADY_REGISTERED beats SCOPE_MISMATCH', () => {
      expect(
        decideApplicationSubmit(
          input({ tokenScope: 'AGENT', phoneAlreadyHasAgent: true }),
        ),
      ).toEqual({ allowed: false, reason: 'PHONE_ALREADY_REGISTERED' });
    });

    it('rejectedMayReapply does not matter', () => {
      expect(
        decideApplicationSubmit(input({ rejectedMayReapply: false })),
      ).toEqual({ allowed: true, action: 'CREATE_PENDING' });
    });
  });

  describe('REJECTED (re-apply is a pending decision)', () => {
    it.each(['APPLICANT', 'AGENT'])(
      'resubmits when rejectedMayReapply is true (%s token)',
      (tokenScope) => {
        expect(
          decideApplicationSubmit(
            input({ tokenScope, existingAgentStatus: 'REJECTED' }),
          ),
        ).toEqual({ allowed: true, action: 'RESUBMIT_PENDING' });
      },
    );

    it('REAPPLY_NOT_ALLOWED when rejectedMayReapply is false', () => {
      expect(
        decideApplicationSubmit(
          input({ existingAgentStatus: 'REJECTED', rejectedMayReapply: false }),
        ),
      ).toEqual({ allowed: false, reason: 'REAPPLY_NOT_ALLOWED' });
    });

    it('ignores phoneAlreadyHasAgent (the record is the caller’s own)', () => {
      expect(
        decideApplicationSubmit(
          input({
            existingAgentStatus: 'REJECTED',
            phoneAlreadyHasAgent: true,
          }),
        ),
      ).toEqual({ allowed: true, action: 'RESUBMIT_PENDING' });
    });
  });

  it('ALREADY_PENDING for PENDING_APPROVAL', () => {
    expect(
      decideApplicationSubmit(
        input({ existingAgentStatus: 'PENDING_APPROVAL' }),
      ),
    ).toEqual({ allowed: false, reason: 'ALREADY_PENDING' });
  });

  it.each(['ACTIVE', 'SUSPENDED', 'TERMINATED'])(
    'ALREADY_AN_AGENT for %s',
    (existingAgentStatus) => {
      for (const tokenScope of ['AGENT', 'APPLICANT']) {
        expect(
          decideApplicationSubmit(input({ tokenScope, existingAgentStatus })),
        ).toEqual({ allowed: false, reason: 'ALREADY_AN_AGENT' });
      }
    },
  );

  it.each(['', 'active', 'DELETED', 'APPLICANT', 'toString'])(
    'UNKNOWN_STATUS for %p',
    (existingAgentStatus) => {
      expect(decideApplicationSubmit(input({ existingAgentStatus }))).toEqual({
        allowed: false,
        reason: 'UNKNOWN_STATUS',
      });
    },
  );

  it.each(['', 'agent', 'ADMIN', 'MEMBER'])(
    'BAD_SCOPE for token scope %p, before anything else',
    (tokenScope) => {
      expect(decideApplicationSubmit(input({ tokenScope }))).toEqual({
        allowed: false,
        reason: 'BAD_SCOPE',
      });
      expect(
        decideApplicationSubmit(
          input({ tokenScope, existingAgentStatus: 'REJECTED' }),
        ),
      ).toEqual({ allowed: false, reason: 'BAD_SCOPE' });
    },
  );
});
