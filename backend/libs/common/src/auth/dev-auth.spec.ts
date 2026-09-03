import {
  DEV_AUTH_HEADER,
  devAuthUid,
  dummyAuthAllows,
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

  describe('DUMMY_OTP_ENABLED off production needs no whitelist', () => {
    // The whitelist off production only ever meant a developer registering
    // each of their own test numbers by hand before they could sign up, on
    // data that is throwaway anyway — and getting
    // "this number is not enabled" on their own machine when they forgot.
    it('admits any well-formed number, listed or not', () => {
      env({ NODE_ENV: 'development', DUMMY_OTP_ENABLED: 'true' });

      expect(dummyAuthAllows(LISTED)).toBe(true);
      expect(dummyAuthAllows(UNLISTED)).toBe(true);
      expect(dummyAuthAllows('+919876543212')).toBe(true);
      expect(readDevAuthPhone(header(UNLISTED))).toBe(UNLISTED);
    });

    it('does not care that the whitelist is empty', () => {
      env({
        NODE_ENV: 'development',
        DUMMY_OTP_ENABLED: 'true',
        DUMMY_OTP_PHONES: '',
      });

      expect(dummyAuthAllows(UNLISTED)).toBe(true);
    });

    it('still refuses a malformed number', () => {
      env({ NODE_ENV: 'development', DUMMY_OTP_ENABLED: 'true' });

      for (const bad of [
        '919876543210',
        '+0123456789',
        '+91 98765 43210',
        'not-a-number',
        '',
        '+91',
      ]) {
        expect(dummyAuthAllows(bad)).toBe(false);
      }
    });

    it('is still off when neither flag is set', () => {
      env({ NODE_ENV: 'development' });

      expect(dummyAuthAllows(UNLISTED)).toBe(false);
      expect(dummyAuthAllows(LISTED)).toBe(false);
    });

    it('is still off once USE_REAL_OTP is set', () => {
      env({
        NODE_ENV: 'development',
        DUMMY_OTP_ENABLED: 'true',
        DEV_AUTH_ENABLED: 'true',
        USE_REAL_OTP: 'true',
      });

      expect(dummyAuthAllows(UNLISTED)).toBe(false);
    });

    it('does NOT widen production, which still needs the list', () => {
      // The one thing this change must not do.
      env({
        NODE_ENV: 'production',
        DUMMY_OTP_ENABLED: 'true',
        DUMMY_OTP_PHONES: LISTED,
      });

      expect(dummyAuthAllows(LISTED)).toBe(true);
      expect(dummyAuthAllows(UNLISTED)).toBe(false);
    });
  });

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

    it('admits ANY well-formed number when the list is unset or empty', () => {
      // The list is an optional narrowing, not a precondition: with none
      // configured the mode admits anything well-formed, production included.
      // This is the deliberate inversion of the old fail-closed default — the
      // app cannot send an SMS, so a signup has to be completable with
      // whatever number the member typed, on whatever server they reach.
      for (const list of [undefined, '', '   ', ',,']) {
        env({
          NODE_ENV: 'production',
          DUMMY_OTP_ENABLED: 'true',
          DUMMY_OTP_PHONES: list,
        });
        expect(dummyOtpPhones().size).toBe(0);
        expect(dummyAuthAllows(LISTED)).toBe(true);
        expect(dummyAuthAllows(UNLISTED)).toBe(true);
        expect(readDevAuthPhone(header(UNLISTED))).toBe(UNLISTED);
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

  // ── the policy as a table ──────────────────────────────────────────────
  //
  // The rule DUMMY_OTP_ENABLED now states, in the order it is evaluated.
  // Written against `dummyAuthAllows` directly because it is the one function
  // both entry points consult — the header and the session endpoint — so a
  // divergence between them is impossible by construction.

  describe('DUMMY_OTP_ENABLED accepts any valid E.164, in any NODE_ENV', () => {
    it('admits an arbitrary number in production', () => {
      env({ NODE_ENV: 'production', DUMMY_OTP_ENABLED: 'true' });

      for (const phone of [
        '+919876543212',
        '+916358494664',
        '+14155550123',
        '+447911123456',
      ]) {
        expect(dummyAuthAllows(phone)).toBe(true);
      }
    });

    it('admits an arbitrary number in production with an empty list', () => {
      env({
        NODE_ENV: 'production',
        DUMMY_OTP_ENABLED: 'true',
        DUMMY_OTP_PHONES: '',
      });

      expect(dummyAuthAllows(UNLISTED)).toBe(true);
    });

    it('narrows to the listed numbers once the list is populated', () => {
      env({
        NODE_ENV: 'production',
        DUMMY_OTP_ENABLED: 'true',
        DUMMY_OTP_PHONES: LISTED,
      });

      // The list tightens; it never enables. This is the one lever that
      // closes the mode down without turning it off.
      expect(dummyAuthAllows(LISTED)).toBe(true);
      expect(dummyAuthAllows(UNLISTED)).toBe(false);
    });

    it('rejects a malformed number however the flags are set', () => {
      env({ NODE_ENV: 'production', DUMMY_OTP_ENABLED: 'true' });

      for (const bad of [
        '919876543210', // no +
        '+0123456789', // leading zero after +
        '+91 98765 43210', // spaces
        '+91-9876543210', // punctuation
        'not-a-number',
        '',
        '+91', // too short
        `+9198765432100000`, // too long
      ]) {
        expect(dummyAuthAllows(bad)).toBe(false);
      }
    });

    it('is off entirely once USE_REAL_OTP is set', () => {
      env({
        NODE_ENV: 'production',
        DUMMY_OTP_ENABLED: 'true',
        DEV_AUTH_ENABLED: 'true',
        USE_REAL_OTP: 'true',
      });

      expect(dummyAuthAllows(LISTED)).toBe(false);
      expect(dummyAuthAllows(UNLISTED)).toBe(false);
      expect(readDevAuthPhone(header(LISTED))).toBeNull();
    });

    it('is off when neither flag is set', () => {
      for (const nodeEnv of ['production', 'development', undefined]) {
        env({ NODE_ENV: nodeEnv });

        expect(dummyAuthAllows(LISTED)).toBe(false);
        expect(dummyAuthAllows(UNLISTED)).toBe(false);
      }
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
      expect(readDevAuthPhone({ [DEV_AUTH_HEADER]: [LISTED, UNLISTED] })).toBe(
        LISTED,
      );
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
