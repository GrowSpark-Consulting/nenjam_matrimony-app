/**
 * Normalisers and maskers for what an agent types into the application and
 * payout-details forms: PAN, UPI id, IFSC and bank account number.
 *
 * Every function is total: it never throws. A normaliser returns the cleaned
 * value or null. A masker shows only the allowed part of a VALID value; for
 * anything invalid (including non-strings) it returns a fixed, fully masked
 * string, so no hidden character can leak through malformed input.
 */

const PAN_PATTERN = /^[A-Z]{5}[0-9]{4}[A-Z]$/;
const UPI_PATTERN = /^[a-z0-9._-]{2,256}@[a-z][a-z0-9]{1,63}$/;
const IFSC_PATTERN = /^[A-Z]{4}0[A-Z0-9]{6}$/;
const BANK_ACCOUNT_PATTERN = /^[0-9]{9,18}$/;

/** Shown in place of anything that is not a valid value. */
export const FULLY_MASKED = '********';

// ASCII-only case changes, so a non-ASCII letter can never turn into an
// accepted ASCII one (e.g. "ſ".toUpperCase() === "S").
const asciiUpper = (value: string): string =>
  value.replace(/[a-z]/g, (ch) => ch.toUpperCase());
const asciiLower = (value: string): string =>
  value.replace(/[A-Z]/g, (ch) => ch.toLowerCase());

/** "abcde1234f" -> "ABCDE1234F"; null unless a valid PAN. */
export function normalizePan(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const value = asciiUpper(raw.trim());
  return PAN_PATTERN.test(value) ? value : null;
}

/** " Ravi.K@OkBank " -> "ravi.k@okbank"; null unless a valid UPI id. */
export function normalizeUpiId(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const value = asciiLower(raw.trim());
  return UPI_PATTERN.test(value) ? value : null;
}

/** "hdfc0001234" -> "HDFC0001234"; null unless a valid IFSC. */
export function normalizeIfsc(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const value = asciiUpper(raw.trim());
  return IFSC_PATTERN.test(value) ? value : null;
}

/** " 123456789012 " -> "123456789012"; digits only, 9 to 18 of them. */
export function normalizeBankAccountNumber(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const value = raw.trim();
  return BANK_ACCOUNT_PATTERN.test(value) ? value : null;
}

/** "ABCDE1234F" -> "******234F" (last 4 characters only). */
export function maskPan(raw: unknown): string {
  const pan = normalizePan(raw);
  if (pan === null) return FULLY_MASKED;
  return `${'*'.repeat(pan.length - 4)}${pan.slice(-4)}`;
}

/** "123456789012" -> "********9012" (last 4 digits only). */
export function maskBankAccount(raw: unknown): string {
  const account = normalizeBankAccountNumber(raw);
  if (account === null) return FULLY_MASKED;
  return `${'*'.repeat(account.length - 4)}${account.slice(-4)}`;
}

/** "ravi.k@okbank" -> "r***@okbank" (first character and the domain only). */
export function maskUpiId(raw: unknown): string {
  const upi = normalizeUpiId(raw);
  if (upi === null) return FULLY_MASKED;
  const at = upi.indexOf('@');
  return `${upi.charAt(0)}***${upi.slice(at)}`;
}
