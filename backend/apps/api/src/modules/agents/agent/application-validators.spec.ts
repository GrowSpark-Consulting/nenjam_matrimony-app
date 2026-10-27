import {
  FULLY_MASKED,
  maskBankAccount,
  maskPan,
  maskUpiId,
  normalizeBankAccountNumber,
  normalizeIfsc,
  normalizePan,
  normalizeUpiId,
} from './application-validators';

const NON_STRINGS: unknown[] = [
  undefined,
  null,
  1234,
  {},
  ['ABCDE1234F'],
  true,
];

describe('normalizePan', () => {
  it.each([
    ['ABCDE1234F', 'ABCDE1234F'],
    ['abcde1234f', 'ABCDE1234F'],
    ['  AbCdE1234f \n', 'ABCDE1234F'],
  ])('%p -> %p', (input, expected) => {
    expect(normalizePan(input)).toBe(expected);
  });

  it.each([
    '',
    'ABCDE1234',
    'ABCDE12345',
    'ABCD12345F',
    'ABCDE1234F1',
    'ABCDE 1234F',
    'ABCDE-1234F',
    '1BCDE1234F',
    'ABCDE1234ſ', // non-ASCII letter that upper-cases to "S"
  ])('rejects %p', (input) => {
    expect(normalizePan(input)).toBeNull();
  });

  it.each(NON_STRINGS)('rejects non-string %p', (input) => {
    expect(normalizePan(input)).toBeNull();
  });
});

describe('normalizeUpiId', () => {
  it.each([
    ['ravi@okbank', 'ravi@okbank'],
    [' Ravi.K@OkBank ', 'ravi.k@okbank'],
    ['ravi_k-1.x@ybl', 'ravi_k-1.x@ybl'],
    ['98765@paytm', '98765@paytm'],
  ])('%p -> %p', (input, expected) => {
    expect(normalizeUpiId(input)).toBe(expected);
  });

  it.each([
    '',
    'ravi',
    '@okbank',
    'r@okbank', // local part shorter than 2
    'ravi@',
    'ravi@o', // domain shorter than 2
    'ravi@1bank', // domain must start with a letter
    'ravi@ok.bank',
    'ravi@ok-bank',
    'ra vi@okbank',
    'ravi@@okbank',
    'ravi@okbank@x',
    'ravi+1@okbank',
    `${'a'.repeat(257)}@okbank`,
    `ravi@a${'b'.repeat(64)}`,
  ])('rejects %p', (input) => {
    expect(normalizeUpiId(input)).toBeNull();
  });

  it('accepts the length limits exactly', () => {
    expect(normalizeUpiId(`${'a'.repeat(256)}@okbank`)).not.toBeNull();
    expect(normalizeUpiId(`ravi@a${'b'.repeat(63)}`)).not.toBeNull();
  });

  it.each(NON_STRINGS)('rejects non-string %p', (input) => {
    expect(normalizeUpiId(input)).toBeNull();
  });
});

describe('normalizeIfsc', () => {
  it.each([
    ['HDFC0001234', 'HDFC0001234'],
    [' hdfc0001234 ', 'HDFC0001234'],
    ['SBIN0ABC123', 'SBIN0ABC123'],
  ])('%p -> %p', (input, expected) => {
    expect(normalizeIfsc(input)).toBe(expected);
  });

  it.each([
    '',
    'HDFC1001234', // fifth character must be 0
    'HDFC000123',
    'HDFC00012345',
    'HDF00001234',
    'HDFC 0001234',
    'HDFC000123$',
  ])('rejects %p', (input) => {
    expect(normalizeIfsc(input)).toBeNull();
  });

  it.each(NON_STRINGS)('rejects non-string %p', (input) => {
    expect(normalizeIfsc(input)).toBeNull();
  });
});

describe('normalizeBankAccountNumber', () => {
  it.each([
    ['123456789', '123456789'],
    ['123456789012345678', '123456789012345678'],
    ['  001234567890 ', '001234567890'],
  ])('%p -> %p', (input, expected) => {
    expect(normalizeBankAccountNumber(input)).toBe(expected);
  });

  it.each([
    '',
    '12345678', // 8 digits
    '1234567890123456789', // 19 digits
    '1234 5678 9012',
    '1234-5678-9012',
    '12345678901a',
    '١٢٣٤٥٦٧٨٩٠', // non-ASCII digits
  ])('rejects %p', (input) => {
    expect(normalizeBankAccountNumber(input)).toBeNull();
  });

  it.each(NON_STRINGS)('rejects non-string %p', (input) => {
    expect(normalizeBankAccountNumber(input)).toBeNull();
  });
});

describe('maskPan', () => {
  it('keeps only the last 4 characters', () => {
    expect(maskPan('ABCDE1234F')).toBe('******234F');
  });

  it('normalises first', () => {
    expect(maskPan(' abcde1234f ')).toBe('******234F');
  });

  it.each(['', 'ABCDE1234', 'XYZ', 'ABCDE12345', ...NON_STRINGS])(
    'fully masks invalid input %p without leaking it',
    (input) => {
      expect(maskPan(input)).toBe(FULLY_MASKED);
    },
  );
});

describe('maskBankAccount', () => {
  it('keeps only the last 4 digits', () => {
    expect(maskBankAccount('123456789012')).toBe('********9012');
    expect(maskBankAccount('123456789')).toBe('*****6789');
  });

  it.each(['', '12345678', '1234 5678 9012', 'abcd', ...NON_STRINGS])(
    'fully masks invalid input %p without leaking it',
    (input) => {
      expect(maskBankAccount(input)).toBe(FULLY_MASKED);
    },
  );
});

describe('maskUpiId', () => {
  it('keeps only the first character and the domain', () => {
    expect(maskUpiId('ravi.k@okbank')).toBe('r***@okbank');
    expect(maskUpiId('98765@paytm')).toBe('9***@paytm');
  });

  it('normalises first', () => {
    expect(maskUpiId(' Ravi.K@OkBank ')).toBe('r***@okbank');
  });

  it('does not reveal the length of the hidden part', () => {
    expect(maskUpiId('ab@okbank')).toBe(maskUpiId('abcdefghij@okbank'));
  });

  it.each(['', 'ravi', 'r@okbank', 'ravi@1bank', 'secret@', ...NON_STRINGS])(
    'fully masks invalid input %p without leaking it',
    (input) => {
      expect(maskUpiId(input)).toBe(FULLY_MASKED);
    },
  );
});

describe('masking never leaks hidden characters', () => {
  it('the fully masked string contains no letters or digits', () => {
    expect(FULLY_MASKED).toMatch(/^\*+$/);
  });

  it('a masked PAN shows none of its first six characters', () => {
    const masked = maskPan('QWERT1234Z');
    expect(masked).not.toMatch(/[QWERT]/);
    expect(masked.slice(0, 6)).toBe('******');
  });

  it('a masked account shows none of its leading digits', () => {
    const masked = maskBankAccount('987654321098');
    expect(masked.slice(0, -4)).toMatch(/^\*+$/);
  });
});
