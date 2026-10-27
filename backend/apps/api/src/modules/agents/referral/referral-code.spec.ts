import {
  generateReferralCode,
  generateUniqueReferralCode,
  REFERRAL_CODE_ALPHABET,
  RandomInt,
} from './referral-code';

/** A random source that returns the given indexes in order, then repeats. */
const sequence = (indexes: number[]): RandomInt => {
  let i = 0;
  return () => indexes[i++ % indexes.length];
};

describe('generateReferralCode', () => {
  it('has a 31-character alphabet with no 0, O, 1, I or L', () => {
    expect(REFERRAL_CODE_ALPHABET).toHaveLength(31);
    expect(new Set(REFERRAL_CODE_ALPHABET).size).toBe(31);
    for (const banned of ['0', 'O', '1', 'I', 'L']) {
      expect(REFERRAL_CODE_ALPHABET).not.toContain(banned);
    }
  });

  it('always matches the format and is 8 characters long', () => {
    for (let i = 0; i < 2000; i++) {
      const code = generateReferralCode();
      expect(code).toMatch(/^NM[2-9A-HJKMNP-Z]{6}$/);
      expect(code).toHaveLength(8);
    }
  });

  it('only ever uses allowed characters after the prefix', () => {
    const allowed = new Set(REFERRAL_CODE_ALPHABET);
    for (let i = 0; i < 2000; i++) {
      for (const ch of generateReferralCode().slice(2)) {
        expect(allowed.has(ch)).toBe(true);
      }
    }
  });

  it('can reach every character of the alphabet', () => {
    const seen = new Set<string>();
    for (let i = 0; i < REFERRAL_CODE_ALPHABET.length; i++) {
      seen.add(generateReferralCode(() => i).charAt(2));
    }
    expect(seen.size).toBe(REFERRAL_CODE_ALPHABET.length);
  });

  it('is predictable with an injected random source', () => {
    expect(generateReferralCode(sequence([0, 1, 2, 3, 4, 5]))).toBe('NM234567');
    expect(generateReferralCode(() => 30)).toBe('NMZZZZZZ');
  });

  it('asks the random source for an index within the alphabet', () => {
    const random = jest.fn<number, [number]>(() => 0);
    generateReferralCode(random);
    expect(random).toHaveBeenCalledTimes(6);
    expect(random).toHaveBeenCalledWith(31);
  });
});

describe('generateUniqueReferralCode', () => {
  it('returns the first code when it is free', async () => {
    const exists = jest.fn().mockResolvedValue(false);
    await expect(generateUniqueReferralCode(exists, 5, () => 0)).resolves.toBe(
      'NM222222',
    );
    expect(exists).toHaveBeenCalledTimes(1);
  });

  it('retries on collision until a free code is found', async () => {
    // Attempt 1 -> NM222222 (taken), 2 -> NM333333 (taken), 3 -> NM444444.
    const random = sequence([
      0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2,
    ]);
    const taken = new Set(['NM222222', 'NM333333']);
    const exists = jest.fn((code: string) => Promise.resolve(taken.has(code)));
    await expect(generateUniqueReferralCode(exists, 5, random)).resolves.toBe(
      'NM444444',
    );
    expect(exists).toHaveBeenCalledTimes(3);
  });

  it('throws a clear error after the attempt limit', async () => {
    const exists = jest.fn().mockResolvedValue(true);
    await expect(generateUniqueReferralCode(exists, 3)).rejects.toThrow(
      'Could not generate a unique referral code after 3 attempts.',
    );
    expect(exists).toHaveBeenCalledTimes(3);
  });

  it.each([0, -1, 1.5, NaN])('rejects maxAttempts %p', async (max) => {
    await expect(
      generateUniqueReferralCode(() => Promise.resolve(false), max),
    ).rejects.toThrow(RangeError);
  });

  it('propagates an error from the exists check', async () => {
    const exists = jest.fn().mockRejectedValue(new Error('db down'));
    await expect(generateUniqueReferralCode(exists, 3)).rejects.toThrow(
      'db down',
    );
  });
});
