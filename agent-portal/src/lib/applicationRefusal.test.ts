import { ApiError } from '../api/errors';
import type { AgentStatus } from '../api/types';
import { applicationRefusal } from './applicationRefusal';

/** Every row of FRONTEND_HANDOFF_DHATRI.md §4.2's refusal table. */
describe('applicationRefusal', () => {
  const e = (status: number, code: string | null, agentStatus?: string, message = 'x') =>
    new ApiError(status, message, {
      code,
      agentStatus: (agentStatus ?? null) as AgentStatus | null,
    });

  it.each([
    ['401 UNAUTHORIZED', e(401, 'UNAUTHORIZED'), { kind: 'verifyAgain' }],
    ['401 TOKEN_EXPIRED', e(401, 'TOKEN_EXPIRED'), { kind: 'verifyAgain' }],
    ['403 + REJECTED', e(403, 'AGENT_NOT_ACTIVE', 'REJECTED'), { kind: 'rejected' }],
    ['403 without status', e(403, 'AGENT_NOT_ACTIVE'), { kind: 'signInAgain' }],
    ['409 + PENDING', e(409, 'APPLICATION_EXISTS', 'PENDING_APPROVAL'), { kind: 'pending' }],
    [
      '409 + ACTIVE',
      e(409, 'APPLICATION_EXISTS', 'ACTIVE'),
      { kind: 'alreadyAgent', agentStatus: 'ACTIVE' },
    ],
    [
      '409 + SUSPENDED',
      e(409, 'APPLICATION_EXISTS', 'SUSPENDED'),
      { kind: 'alreadyAgent', agentStatus: 'SUSPENDED' },
    ],
    [
      '409 + TERMINATED',
      e(409, 'APPLICATION_EXISTS', 'TERMINATED'),
      { kind: 'alreadyAgent', agentStatus: 'TERMINATED' },
    ],
    ['409 without status', e(409, 'APPLICATION_EXISTS'), { kind: 'signInAgain' }],
    ['409 with an unknown status', e(409, 'APPLICATION_EXISTS', 'SOMETHING_NEW'), { kind: 'signInAgain' }],
  ])('%s', (_label, error, expected) => {
    expect(applicationRefusal(error)).toEqual(expected);
  });

  it('400: finds the fields the message names, never guesses others', () => {
    expect(
      applicationRefusal(
        e(400, 'VALIDATION_FAILED', undefined, 'name must be 2-100 characters, pan is not valid'),
      ),
    ).toEqual({ kind: 'invalidFields', fields: ['name', 'pan'] });
    expect(
      applicationRefusal(e(400, 'VALIDATION_FAILED', undefined, 'Some details are not valid.')),
    ).toEqual({ kind: 'invalidFields', fields: [] });
    // "statement" must not be read as the "state" field.
    expect(
      applicationRefusal(e(400, 'VALIDATION_FAILED', undefined, 'a statement about city')),
    ).toEqual({ kind: 'invalidFields', fields: ['city'] });
  });

  it('anything else is not a documented refusal', () => {
    expect(applicationRefusal(e(500, null))).toBeNull();
    expect(applicationRefusal(e(409, 'SOMETHING_ELSE'))).toBeNull();
    expect(applicationRefusal(new Error('x'))).toBeNull();
    expect(applicationRefusal(ApiError.network())).toBeNull();
  });
});
