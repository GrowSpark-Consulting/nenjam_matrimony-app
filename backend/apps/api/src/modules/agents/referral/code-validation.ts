/**
 * Helpers for POST /referrals/codes/validate, which anyone can call before
 * signing up. It reveals an agent's first name and last initial, so it is
 * attempt-limited per IP and per code, and an invalid answer never says why.
 */
import { toDisplayName } from './agent-referral-view';

export interface CodeValidationAttemptInput {
  /** Attempts already made from this IP in the current window. */
  ipAttempts: number;
  /** Attempts already made for this code in the current window. */
  codeAttempts: number;
  ipLimit: number;
  codeLimit: number;
}

export type CodeValidationAttemptDecision =
  { allowed: true } | { allowed: false; reason: 'IP_LIMIT' | 'CODE_LIMIT' };

function assertCount(name: string, value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${name} must be a non-negative integer.`);
  }
}

function assertLimit(name: string, value: number): void {
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new RangeError(`${name} must be a positive integer.`);
  }
}

/** Blocked once attempts reach the limit. The IP limit is checked first. */
export function decideCodeValidationAttempt(
  input: CodeValidationAttemptInput,
): CodeValidationAttemptDecision {
  assertCount('ipAttempts', input.ipAttempts);
  assertCount('codeAttempts', input.codeAttempts);
  assertLimit('ipLimit', input.ipLimit);
  assertLimit('codeLimit', input.codeLimit);

  if (input.ipAttempts >= input.ipLimit) {
    return { allowed: false, reason: 'IP_LIMIT' };
  }
  if (input.codeAttempts >= input.codeLimit) {
    return { allowed: false, reason: 'CODE_LIMIT' };
  }
  return { allowed: true };
}

export interface ValidateResponseInput {
  found: boolean;
  codeActive: boolean;
  agentStatus: string | null;
  firstName: string | null;
  lastName?: string | null;
}

export interface ValidateResponse {
  valid: boolean;
  agentDisplayName: string | null;
}

/**
 * The response body. Every invalid case (unknown code, inactive code, agent
 * not ACTIVE) returns exactly the same `{ valid: false, agentDisplayName: null }`
 * so the response cannot be used to tell them apart.
 */
export function toValidateResponse(
  input: ValidateResponseInput,
): ValidateResponse {
  if (!input.found || !input.codeActive || input.agentStatus !== 'ACTIVE') {
    return { valid: false, agentDisplayName: null };
  }
  const name = toDisplayName(input.firstName ?? '', input.lastName);
  return { valid: true, agentDisplayName: name === '' ? null : name };
}
