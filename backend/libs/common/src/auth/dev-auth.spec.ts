import {
  DEV_AUTH_HEADER,
  devAuthUid,
  dummyOtpPhones,
  isDevAuthEnabled,
  isDummyOtpEnabled,
  isRealOtpForced,
  readDevAuthPhone,
} from './dev-auth';

/**
 * Dummy-OTP auth is an authentication bypass that exists so signup can work
 * before Firebase SMS billing is enabled. Everything worth testing is about
 * where it does NOT apply: the failure that matters is never "it did not work
 * in dev", it is "it worked somewhere, or for someone, it should not have".
 */
describe('dummy-OTP authentication', () => {
  const original = { ...process.env };

  afterEach(() => {
    process.env = { ...original };
  });

  const env = (vars: Record<string, string | undefined>) => {
    for (const key of [
      'NODE_ENV',
      'DEV_AUTH_ENABLED',
      'DUMMY_OTP_ENABLED',
      'DUMMY_OTP_PHONES',
      'USE_REAL_OTP',
    ]) {
      delete process.env[key];
    }
    for (const [key, value] of Object.entries(vars)) {
      if (value !== undefined) process.env[key] = value;
    }
  };

  const LISTED = '+919876543210';
  const UNLISTED = '+919999999999';
  const header = (phone: string) => ({ [DEV_AUTH_HEADER]: phone });

  // ── development ────────────────────────────────────────────────────────

  describe('development dummy OTP', () => {
    it('works with the flag set, for any well-formed number', () => {
      env({ NODE_ENV: 'development', DEV_AUTH_ENABLED: 'true' });
      expect(isDevAuthEnabled()).toBe(true);
      expect(readDevAuthPhone(header(UNLISTED))).toBe(UNLISTED);
    });

    it('is off unless the flag is deliberately set', () => {
      env({ NODE_ENV: 'development' });
      expect(isDevAuthEnabled()).toBe(false);
      expect(readDevAuthPhone(header(LISTED))).toBeNull();
    });

    it('treats anything but the exact string "true" as off', () => {
      for (const value of ['1', 'yes', 'TRUE', 'on', '']) {
        env({ NODE_ENV: 'development', DEV_AUTH_ENABLED: value });
        expect(isDevAuthEnabled()).toBe(false);
      }
    });
  });

  // ── the protection that must not regress ───────────────────────────────

  describe('DEV_AUTH_ENABLED grants nothing in production', () => {
    it('is off in production even when explicitly enabled', () => {
      env({ NODE_ENV: 'production', DEV_AUTH_ENABLED: 'true' });
      expect(isDevAuthEnabled()).toBe(false);
      expect(readDevAuthPhone(header(LISTED))).toBeNull();
    });

    it('stays off in production even with a number that is whitelisted', () => {
      // The whitelist belongs to the DUMMY_OTP_ENABLED mode. Being listed must
      // not make the development switch work in production.
      env({
        NODE_ENV: 'production',
        DEV_AUTH_ENABLED: 'true',
        DUMMY_OTP_PHONES: LISTED,
      });
      expect(readDevAuthPhone(header(LISTED))).toBeNull();
    });
  });

  // ── production ─────────────────────────────────────────────────────────

  describe('production dummy OTP', () => {
    it('works only when explicitly enabled, for a whitelisted number', () => {
      env({
        NODE_ENV: 'production',
        DUMMY_OTP_ENABLED: 'true',
        DUMMY_OTP_PHONES: LISTED,
      });
      expect(isDummyOtpEnabled()).toBe(true);
      expect(readDevAuthPhone(header(LISTED))).toBe(LISTED);
    });

    it('rejects non-whitelisted numbers', () => {
      env({
        NODE_ENV: 'production',
        DUMMY_OTP_ENABLED: 'true',
        DUMMY_OTP_PHONES: LISTED,
      });
      expect(readDevAuthPhone(header(UNLISTED))).toBeNull();
    });

    it('is disabled when the flag is false', () => {
      env({
        NODE_ENV: 'production',
        DUMMY_OTP_ENABLED: 'false',
        DUMMY_OTP_PHONES: LISTED,
      });
      expect(isDummyOtpEnabled()).toBe(false);
      expect(readDevAuthPhone(header(LISTED))).toBeNull();
    });

    it('admits nobody when the whitelist is unset or empty', () => {
      for (const list of [undefined, '', '   ', ',,']) {
        env({
          NODE_ENV: 'production',
          DUMMY_OTP_ENABLED: 'true',
          DUMMY_OTP_PHONES: list,
        });
        expect(dummyOtpPhones().size).toBe(0);
        expect(readDevAuthPhone(header(LISTED))).toBeNull();
      }
    });

    it('drops malformed whitelist entries rather than widening the list', () => {
      env({
        NODE_ENV: 'production',
        DUMMY_OTP_ENABLED: 'true',
        DUMMY_OTP_PHONES: `not-a-number, ${LISTED} ,919876543211,+0123`,
      });
      const phones = dummyOtpPhones();
      expect(phones.has(LISTED)).toBe(true);
      expect(phones.size).toBe(1);
    });
  });

  // ── the switch back to real Firebase ───────────────────────────────────

  describe('USE_REAL_OTP=true restores the real Firebase path', () => {
    it('disables the development mode', () => {
      env({
        NODE_ENV: 'development',
        DEV_AUTH_ENABLED: 'true',
        USE_REAL_OTP: 'true',
      });
      expect(isRealOtpForced()).toBe(true);
      expect(isDevAuthEnabled()).toBe(false);
      expect(readDevAuthPhone(header(LISTED))).toBeNull();
    });

    it('disables the production mode even for a whitelisted number', () => {
      env({
        NODE_ENV: 'production',
        DUMMY_OTP_ENABLED: 'true',
        DUMMY_OTP_PHONES: LISTED,
        USE_REAL_OTP: 'true',
      });
      expect(isDummyOtpEnabled()).toBe(false);
      expect(readDevAuthPhone(header(LISTED))).toBeNull();
    });
  });

  // ── header handling, shared by both modes ──────────────────────────────

  describe('reading the header', () => {
    beforeEach(() => {
      env({ NODE_ENV: 'development', DEV_AUTH_ENABLED: 'true' });
    });

    it('trims surrounding whitespace', () => {
      expect(readDevAuthPhone(header(`  ${LISTED} `))).toBe(LISTED);
    });

    it('returns null when the header is absent', () => {
      expect(readDevAuthPhone({})).toBeNull();
    });

    it('takes the first value when the header is repeated', () => {
      expect(
        readDevAuthPhone({ [DEV_AUTH_HEADER]: [LISTED, UNLISTED] }),
      ).toBe(LISTED);
    });

    it.each([
      ['not a number', 'nine one two'],
      ['missing +', '919876543210'],
      ['too short', '+123'],
      ['leading zero after +', '+0919876543210'],
      ['empty', ''],
      ['SQL-ish', "+91' OR 1=1--"],
      ['a path', '../../etc/passwd'],
    ])('rejects %s', (_label, value) => {
      expect(readDevAuthPhone(header(value))).toBeNull();
    });
  });

  describe('uid namespacing', () => {
    it('cannot collide with a Firebase uid', () => {
      expect(devAuthUid(LISTED)).toBe(`devauth:${LISTED}`);
    });
  });
});
