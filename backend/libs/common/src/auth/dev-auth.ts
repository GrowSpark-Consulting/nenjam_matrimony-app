/**
 * DUMMY-OTP AUTHENTICATION — temporary scaffolding, not a feature.
 *
 * The app's signup ends in a dummy OTP screen (`MockOtpVerifier`, Flutter
 * side) that accepts any code and mints no Firebase session, because real
 * Firebase Phone Auth needs SMS billing this project has not enabled yet.
 * Without a session the client has no ID token, so every authenticated request
 * is rejected and no profile can ever be created. This module is the seam that
 * closes that gap.
 *
 * It is a genuine authentication bypass — whoever can set one HTTP header
 * becomes that phone number — so the whole file is about bounding where it
 * applies and to whom.
 *
 * ## Two modes, deliberately different in strictness
 *
 * **Development** (`NODE_ENV !== 'production'` AND either
 * `DEV_AUTH_ENABLED=true` or `DUMMY_OTP_ENABLED=true`): any well-formed
 * number. A developer's own machine, throwaway data, and a flag that has to
 * be set by hand. No whitelist — off production it only ever meant a
 * developer registering each of their own test numbers by hand before they
 * could sign up, against data that is disposable anyway.
 *
 * **Production** (`DUMMY_OTP_ENABLED=true` AND the number is listed in
 * `DUMMY_OTP_PHONES`): only the numbers the operator explicitly configured.
 * This is what lets a deployed build demo the flow before billing is on, and
 * it is why the production mode is a whitelist rather than the development
 * rule with its environment check removed. An unset or empty whitelist admits
 * nobody, so the mode fails closed.
 *
 * Every account reachable this way can be signed into by anyone who knows the
 * number, with no credential of any kind. Whitelist only throwaway test
 * numbers — never a real member's.
 *
 * ## What stays true in both modes
 *
 * `USE_REAL_OTP=true` switches everything here off, which is the one-flag path
 * back to real Firebase Phone Auth when billing is enabled — no auth refactor.
 *
 * `NODE_ENV=production` + `DEV_AUTH_ENABLED=true` still grants nothing. That
 * protection is unchanged: production access requires the separate
 * `DUMMY_OTP_ENABLED` flag *and* a listed number.
 *
 * Nothing here forges a Firebase ID token, and `verifyIdToken` is never called
 * with anything this module produced. FirebaseAuthGuard consults it only when
 * a request carries no `Authorization` header at all, so bearer-token
 * verification is untouched in every mode.
 *
 * ## Removal
 *
 * Delete this file, its call sites in FirebaseAuthGuard, and the Flutter
 * `DevAuthSession` together once real phone verification is switched on.
 */

/** The header a dummy-authenticated client sends instead of a bearer token. */
export const DEV_AUTH_HEADER = 'x-dev-auth-phone';

/**
 * Firebase UIDs are opaque strings, so these sessions get their own namespace
 * rather than risking a collision. The prefix also makes every row this path
 * created greppable — `SELECT * FROM users WHERE firebase_uid LIKE
 * 'devauth:%'` is the complete list, which is what makes them safe to purge.
 */
export const DEV_AUTH_UID_PREFIX = 'devauth:';

/** E.164, the same shape the Flutter phone field emits. */
const E164 = /^\+[1-9]\d{7,14}$/;

const isTrue = (value: string | undefined): boolean => value === 'true';

/**
 * The master switch back to real Firebase Phone Auth. When set, every dummy
 * path below is off regardless of any other flag — so enabling billing is a
 * one-variable change, not a code change.
 */
export function isRealOtpForced(): boolean {
  return isTrue(process.env.USE_REAL_OTP);
}

/**
 * Development mode: any well-formed number, on a non-production environment,
 * with the flag deliberately set. Both conditions default to off — an absent
 * `DEV_AUTH_ENABLED` is off, and this is the switch that must never be able to
 * grant anything in production.
 */
export function isDevAuthEnabled(): boolean {
  if (isRealOtpForced()) return false;
  return (
    process.env.NODE_ENV !== 'production' &&
    isTrue(process.env.DEV_AUTH_ENABLED)
  );
}

/**
 * Production mode: explicitly enabled, and only for listed numbers.
 *
 * Independent of NODE_ENV on purpose. Gating it on "is production" would mean
 * the same deployment behaves differently depending on a variable that is
 * routinely unset, and a whitelist is safe to evaluate anywhere — the
 * restriction that matters is the list itself, not the environment name.
 */
export function isDummyOtpEnabled(): boolean {
  if (isRealOtpForced()) return false;
  return isTrue(process.env.DUMMY_OTP_ENABLED);
}

/**
 * The configured test numbers, or an empty set.
 *
 * Read on every call rather than cached so a deployment can change the list
 * without a restart-shaped surprise, and so tests can vary it. Malformed
 * entries are dropped rather than tolerated: a typo must shrink the whitelist,
 * never widen it.
 */
export function dummyOtpPhones(): ReadonlySet<string> {
  const raw = process.env.DUMMY_OTP_PHONES ?? '';
  return new Set(
    raw
      .split(',')
      .map((entry) => entry.trim())
      .filter((entry) => E164.test(entry)),
  );
}

export function devAuthUid(phoneE164: string): string {
  return `${DEV_AUTH_UID_PREFIX}${phoneE164}`;
}

/**
 * Whether the dummy-OTP arrangement may vouch for [phoneE164] at all — the
 * two-mode policy above, stated once so that every entry point answers it
 * identically.
 *
 * [readDevAuthPhone] applies it to the header a request carries.
 * `POST /auth/dummy-otp/session` applies it to the number in a request body:
 * that endpoint mints a REAL Firebase session for a number nobody has sent an
 * SMS to, which is the same bypass this file already governs and must never be
 * a wider one. Same flags, same whitelist, same fail-closed default.
 */
export function dummyAuthAllows(phoneE164: string): boolean {
  // The master switch first: with real phone auth on, nothing below applies.
  if (isRealOtpForced()) return false;

  // A malformed value is never an identity, whatever the mode.
  if (!E164.test(phoneE164)) return false;

  // Off unless an operator deliberately set a flag. Both default to absent,
  // so an unconfigured environment admits nobody.
  if (!isDevAuthEnabled() && !isDummyOtpEnabled()) return false;

  // Outside production, either flag means "the dummy OTP is the verification
  // mechanism here", and it admits ANY well-formed number. Requiring a
  // whitelist off production made a developer register every test number by
  // hand before they could sign up on their own machine — a list that can
  // only ever be out of date, guarding data that is already throwaway.
  //
  // This leans on NODE_ENV being set on real deployments, which it is: the
  // deployed start command is `start:prod`, and that sets
  // NODE_ENV=production itself (see package.json / railway.toml). An
  // environment that serves real members with NODE_ENV unset would fall into
  // this branch, which is the one thing to keep true when changing how the
  // API is started.
  if (process.env.NODE_ENV !== 'production') return true;

  // In production, only the numbers the operator configured — unchanged, and
  // an unset or empty list admits nobody, so the mode still fails closed.
  return dummyOtpPhones().has(phoneE164);
}

/**
 * The phone number a dummy-auth request may be authenticated as, or null.
 *
 * Null whenever every mode is off, the header is absent or malformed, or the
 * number is not permitted by whichever mode is active — an unparseable header
 * is treated as no header at all, so a malformed value can never become an
 * identity.
 */
export function readDevAuthPhone(
  headers: Record<string, string | string[] | undefined>,
): string | null {
  const raw = headers[DEV_AUTH_HEADER];
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (typeof value !== 'string') return null;

  const phone = value.trim();
  return dummyAuthAllows(phone) ? phone : null;
}
