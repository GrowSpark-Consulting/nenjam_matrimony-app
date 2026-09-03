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
 * ## One switch, and an optional narrowing
 *
 * `DUMMY_OTP_ENABLED=true` admits **any well-formed E.164 number, in every
 * environment, `NODE_ENV=production` included**. `DEV_AUTH_ENABLED=true` does
 * the same off production. That is the point of the mode: the app cannot send
 * an SMS yet, so signup has to be completable with whatever number a member
 * types, on whatever server the build is pointed at. A per-number list instead
 * meant "this number is not enabled for dummy OTP" on a server the operator
 * controls, for a number they had just invented.
 *
 * `DUMMY_OTP_PHONES` is an OPTIONAL narrowing, not a precondition: non-empty,
 * it restricts sign-in to exactly the listed numbers; empty or unset, any
 * well-formed number is accepted. Setting it can only ever tighten.
 *
 * ## What this costs, stated plainly
 *
 * With this enabled and no list, ANYONE who can reach the API can sign in as
 * ANY phone number, with no credential of any kind, and can create unlimited
 * accounts. The endpoint's name is not obscurity and the rate limit is not
 * protection. This is acceptable only while every account in the database is
 * disposable.
 *
 * Two ways to close it, both one variable and no code change:
 * `USE_REAL_OTP=true` (which also restores real Firebase Phone Auth — the
 * actual fix, once SMS billing is on), or a populated `DUMMY_OTP_PHONES`.
 * Do one of them before real members sign up.
 *
 * ## What stays true in every mode
 *
 * `USE_REAL_OTP=true` switches everything here off, which is the one-flag path
 * back to real Firebase Phone Auth when billing is enabled — no auth refactor.
 *
 * Both flags default to absent, so an environment that configures neither
 * admits nobody. A malformed number is never an identity.
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
 * The dummy OTP is the verification mechanism on this server — for any
 * well-formed number, in any environment.
 *
 * Independent of NODE_ENV on purpose: gating it on "is production" would mean
 * the same deployment behaves differently depending on a variable that is
 * routinely unset. What bounds this mode is the flag itself and the optional
 * [dummyOtpPhones] narrowing, not the environment name.
 */
export function isDummyOtpEnabled(): boolean {
  if (isRealOtpForced()) return false;
  return isTrue(process.env.DUMMY_OTP_ENABLED);
}

/**
 * The numbers dummy sign-in has been narrowed to, or an empty set meaning
 * "not narrowed" — any well-formed number is then accepted. See
 * [dummyAuthAllows]; this list can only ever tighten, never enable.
 *
 * Read on every call rather than cached so a deployment can change the list
 * without a restart-shaped surprise, and so tests can vary it. Malformed
 * entries are dropped rather than tolerated: a typo must shrink the list,
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
 * policy above, stated once so that every entry point answers it identically.
 *
 * [readDevAuthPhone] applies it to the header a request carries.
 * `POST /auth/dummy-otp/session` applies it to the number in a request body:
 * that endpoint mints a REAL Firebase session for a number nobody has sent an
 * SMS to, which is the same bypass this file already governs and must never be
 * a wider one. Same flags, same optional narrowing.
 *
 * In order:
 *   USE_REAL_OTP=true                  -> false, whatever else is set
 *   malformed number                   -> false, in every mode
 *   neither flag set                   -> false (both default to absent)
 *   DUMMY_OTP_ENABLED + empty list     -> true, any NODE_ENV
 *   DUMMY_OTP_ENABLED + non-empty list -> only the listed numbers
 *   DEV_AUTH_ENABLED off production    -> true
 */
export function dummyAuthAllows(phoneE164: string): boolean {
  // The master switch first: with real phone auth on, nothing below applies.
  if (isRealOtpForced()) return false;

  // A malformed value is never an identity, whatever the mode.
  if (!E164.test(phoneE164)) return false;

  // Off unless an operator deliberately set a flag. Both default to absent,
  // so an unconfigured environment admits nobody.
  if (!isDevAuthEnabled() && !isDummyOtpEnabled()) return false;

  // When DUMMY_OTP_ENABLED is on, any well-formed number is accepted
  // regardless of NODE_ENV. This lets a deployed build demo the full signup
  // flow before SMS billing is enabled without maintaining a phone whitelist.
  // When DUMMY_OTP_PHONES is set it still narrows access, but an empty list
  // no longer blocks everyone.
  if (isDummyOtpEnabled()) {
    const whitelist = dummyOtpPhones();
    return whitelist.size === 0 || whitelist.has(phoneE164);
  }

  // Dev-auth (non-production only) admits any well-formed number.
  return true;
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
