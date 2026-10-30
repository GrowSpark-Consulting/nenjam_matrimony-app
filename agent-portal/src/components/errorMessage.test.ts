import { describe, expect, it } from 'vitest';
import { ApiError, toApiError } from '../api/errors';
import {
  errorMessage,
  FEATURE_UNAVAILABLE_MESSAGE,
  OTP_DELIVERY_UNAVAILABLE_MESSAGE,
  PROGRAM_UNAVAILABLE_MESSAGE,
} from './ErrorText';

/** A Nest-shaped 503 body with a contract `code`. */
const unavailable = (code: string) =>
  toApiError(
    503,
    { statusCode: 503, error: 'Service Unavailable', code, message: 'internal detail' },
    null,
  );

describe('errorMessage', () => {
  it('503 AGENT_PROGRAM_UNAVAILABLE says the program is not available yet', () => {
    expect(errorMessage(unavailable('AGENT_PROGRAM_UNAVAILABLE'))).toBe(
      PROGRAM_UNAVAILABLE_MESSAGE,
    );
  });

  it('503 IDENTIFIER_HASHING_UNAVAILABLE says the feature is not available yet', () => {
    const message = errorMessage(unavailable('IDENTIFIER_HASHING_UNAVAILABLE'));
    expect(message).toBe(FEATURE_UNAVAILABLE_MESSAGE);
    expect(message).not.toContain('internal detail');
  });

  it('503 OTP_DELIVERY_UNAVAILABLE says no code can be sent to this number yet', () => {
    const message = errorMessage(unavailable('OTP_DELIVERY_UNAVAILABLE'));
    expect(message).toBe(OTP_DELIVERY_UNAVAILABLE_MESSAGE);
    expect(message).not.toContain('internal detail');
  });

  it("a 404 with no code (routes switched off) never shows Nest's route text", () => {
    const error = toApiError(
      404,
      { statusCode: 404, error: 'Not Found', message: 'Cannot POST /agent/auth/otp/request' },
      null,
    );
    expect(errorMessage(error)).toBe(PROGRAM_UNAVAILABLE_MESSAGE);
    expect(errorMessage(error)).not.toContain('/agent/');
  });

  it('a documented 404 keeps the server sentence', () => {
    const error = new ApiError(404, 'No such referral.', { code: 'REFERRAL_NOT_FOUND' });
    expect(errorMessage(error)).toBe('No such referral.');
  });

  it('any other 5xx is the fixed "try again shortly" sentence', () => {
    expect(errorMessage(unavailable('SOMETHING_NEW'))).toBe(
      'The service is having trouble right now. Please try again shortly.',
    );
  });

  describe('429 RATE_LIMITED', () => {
    const limited = (retryAfter: string | null) =>
      toApiError(
        429,
        { statusCode: 429, error: 'Too Many Requests', code: 'RATE_LIMITED', message: 'x' },
        retryAfter,
      );

    it('uses the Retry-After seconds', () => {
      const error = limited('30');
      expect(error.retryAfterSeconds).toBe(30);
      expect(errorMessage(error)).toBe('Too many tries, please wait 30 seconds and try again.');
    });

    it('no header: a wait message with no invented time', () => {
      const error = limited(null);
      expect(error.retryAfterSeconds).toBeNull();
      expect(errorMessage(error)).toBe('Too many tries, please wait and try again.');
    });

    it('a malformed or non-positive header is ignored, not guessed', () => {
      for (const header of ['soon', '', '-5', '0', 'Wed, 21 Oct 2026 07:28:00 GMT']) {
        const error = limited(header);
        expect(error.retryAfterSeconds, header).toBeNull();
        expect(errorMessage(error), header).toBe('Too many tries, please wait and try again.');
      }
    });
  });
});
