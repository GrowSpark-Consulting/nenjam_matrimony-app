/** NM + 6 characters, none of 0, O, 1, I, L. Same alphabet as the generator. */
const REFERRAL_CODE_PATTERN = /^NM[2-9A-HJKMNP-Z]{6}$/;

/**
 * Turns what a person typed or pasted into a referral code, or null.
 *
 * Trims, upper-cases, removes spaces and hyphens, then accepts only a
 * well-formed code. Confusing characters are NOT corrected (an `O` is not
 * turned into a `0`): a code that does not match is simply not a code.
 *
 * Upper-casing is ASCII-only on purpose. `String.prototype.toUpperCase` maps
 * some non-ASCII letters (e.g. the long s "ſ") onto ASCII ones, which would
 * accept text nobody typed as a code.
 */
export function normalizeReferralCode(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const cleaned = raw
    .trim()
    .replace(/[a-z]/g, (ch) => ch.toUpperCase())
    .replace(/[\s-]/g, '');
  return REFERRAL_CODE_PATTERN.test(cleaned) ? cleaned : null;
}
