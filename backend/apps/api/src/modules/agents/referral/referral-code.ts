import { randomInt } from 'crypto';

/**
 * Agent referral codes: "NM" + 6 characters. The alphabet leaves out 0, O, 1,
 * I and L so a code read aloud or copied by hand is not misread.
 */
export const REFERRAL_CODE_PREFIX = 'NM';
export const REFERRAL_CODE_LENGTH = 6;
export const REFERRAL_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/** Returns an integer in [0, maxExclusive). Injectable so tests are deterministic. */
export type RandomInt = (maxExclusive: number) => number;

const secureRandomInt: RandomInt = (maxExclusive) => randomInt(maxExclusive);

export function generateReferralCode(
  random: RandomInt = secureRandomInt,
): string {
  let suffix = '';
  for (let i = 0; i < REFERRAL_CODE_LENGTH; i++) {
    suffix += REFERRAL_CODE_ALPHABET[random(REFERRAL_CODE_ALPHABET.length)];
  }
  return REFERRAL_CODE_PREFIX + suffix;
}

/**
 * Generates a code for which `exists` is false, retrying on collision.
 * Throws once `maxAttempts` codes in a row were already taken.
 *
 * The caller must still rely on the database unique constraint: `exists` and
 * the later insert are not atomic.
 */
export async function generateUniqueReferralCode(
  exists: (code: string) => Promise<boolean>,
  maxAttempts: number,
  random: RandomInt = secureRandomInt,
): Promise<string> {
  if (!Number.isInteger(maxAttempts) || maxAttempts < 1) {
    throw new RangeError('maxAttempts must be a positive integer.');
  }
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const code = generateReferralCode(random);
    if (!(await exists(code))) return code;
  }
  throw new Error(
    `Could not generate a unique referral code after ${maxAttempts} attempts.`,
  );
}
