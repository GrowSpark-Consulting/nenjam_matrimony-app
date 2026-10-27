import { normalizeReferralCode } from './normalize-referral-code';

describe('normalizeReferralCode', () => {
  it('accepts a well-formed code unchanged', () => {
    expect(normalizeReferralCode('NM7K2P9X')).toBe('NM7K2P9X');
  });

  it('upper-cases', () => {
    expect(normalizeReferralCode('nm7k2p9x')).toBe('NM7K2P9X');
    expect(normalizeReferralCode('Nm7k2P9x')).toBe('NM7K2P9X');
  });

  it('trims surrounding whitespace', () => {
    expect(normalizeReferralCode('  NM7K2P9X \n')).toBe('NM7K2P9X');
  });

  it('removes spaces and hyphens anywhere', () => {
    expect(normalizeReferralCode('NM 7K2 P9X')).toBe('NM7K2P9X');
    expect(normalizeReferralCode('NM-7K2-P9X')).toBe('NM7K2P9X');
    expect(normalizeReferralCode(' nm - 7k2p 9x ')).toBe('NM7K2P9X');
  });

  describe('rejects', () => {
    it.each([
      ['an empty string', ''],
      ['only whitespace', '   '],
      ['no prefix', '7K2P9X'],
      ['a wrong prefix', 'XX7K2P9X'],
      ['too short', 'NM7K2P9'],
      ['too long', 'NM7K2P9XA'],
      ['other punctuation', 'NM7K2_P9X'],
      ['a dot', 'NM7K2.P9X'],
      ['an en dash instead of a hyphen', 'NM–7K2P9X'],
    ])('%s', (_label, input) => {
      expect(normalizeReferralCode(input)).toBeNull();
    });

    it.each(['0', 'O', '1', 'I', 'L'])(
      'the confusing character %s, without correcting it',
      (ch) => {
        expect(normalizeReferralCode(`NM${ch}K2P9X`)).toBeNull();
        expect(normalizeReferralCode(`NM7K2P9${ch.toLowerCase()}`)).toBeNull();
      },
    );

    it('a non-ASCII letter that upper-cases to an allowed ASCII one', () => {
      // "ſ".toUpperCase() === "S"
      expect(normalizeReferralCode('NM7K2P9ſ')).toBeNull();
      expect(normalizeReferralCode('NM7K2P9K')).toBeNull(); // Kelvin sign
    });

    it.each([
      ['undefined', undefined],
      ['null', null],
      ['a number', 12345678],
      ['an object', {}],
      ['an array', ['NM7K2P9X']],
      ['a boolean', true],
    ])('non-string input: %s', (_label, input) => {
      expect(normalizeReferralCode(input)).toBeNull();
    });
  });
});
