import {
  IdentifierHasher,
  normalizeIdentifier,
  parseIdentifierPeppers,
} from './identifier-hash';

const SECRET_1 = 'a'.repeat(32);
const SECRET_2 = 'b'.repeat(40);
const pepper = (version: string, secret: string) => ({
  version,
  secret: Buffer.from(secret),
});

describe('IdentifierHasher', () => {
  const hasher = new IdentifierHasher([pepper('v1', SECRET_1)]);

  it('writes "<version>:<hex>" and never contains the input', () => {
    const hash = hasher.hash('EMAIL', 'Priya@Example.com');
    expect(hash).toMatch(/^v1:[0-9a-f]{64}$/);
    expect(hash.toLowerCase()).not.toContain('priya');
  });

  it.each([
    ['PHONE', '+91 98765 43210', '+919876543210'],
    ['PHONE', '098765-43210', '9876543210'],
    ['PHONE', '00919876543210', '919876543210'],
    ['EMAIL', '  Priya@Example.COM ', 'priya@example.com'],
    ['PAN', 'abcde 1234f', 'ABCDE1234F'],
    ['IP', '::ffff:203.0.113.9', '203.0.113.9'],
    ['IP', '::FFFF:CB00:7109', '203.0.113.9'],
    ['IP', '2001:0db8:0000:0000:0000:0000:0000:0001', '2001:db8::1'],
    ['IP', 'fe80::1%eth0', 'FE80::1'],
    ['UPI', ' Priya.K@OkICICI ', 'priya.k@okicici'],
  ] as const)('%s: "%s" and "%s" are one identifier', (kind, a, b) => {
    expect(hasher.hash(kind, a)).toBe(hasher.hash(kind, b));
  });

  it('gives different hashes for a different kind or value', () => {
    expect(hasher.hash('PAN', 'ABCDE1234F')).not.toBe(
      hasher.hash('EMAIL', 'ABCDE1234F'),
    );
    expect(hasher.hash('PHONE', '+919876543210')).not.toBe(
      hasher.hash('PHONE', '+919876543211'),
    );
  });

  it('depends on the pepper', () => {
    const other = new IdentifierHasher([pepper('v1', SECRET_2)]);
    expect(other.hash('PAN', 'ABCDE1234F')).not.toBe(
      hasher.hash('PAN', 'ABCDE1234F'),
    );
  });

  it('hashes with the newest pepper and matches older ones through hashAll', () => {
    const rotated = new IdentifierHasher([
      pepper('v2', SECRET_2),
      pepper('v1', SECRET_1),
    ]);
    const stored = hasher.hash('PHONE', '+919876543210');
    expect(rotated.hash('PHONE', '+919876543210')).toMatch(/^v2:/);
    expect(rotated.hashAll('PHONE', '9876543210')).toEqual([
      rotated.hash('PHONE', '+919876543210'),
      stored,
    ]);
  });

  it.each([
    ['PHONE', '   '],
    ['PHONE', '12345'],
    ['PHONE', 'call me'],
    ['IP', '203.0.113.999'],
    ['IP', 'localhost'],
    ['EMAIL', ''],
    ['UPI', 'no-at-sign'],
    ['UPI', 'a@1bank'],
  ] as const)('refuses %s "%s" with a RangeError', (kind, value) => {
    expect(() => hasher.hash(kind, value)).toThrow(RangeError);
  });

  it('refuses weak, repeated or badly named peppers', () => {
    expect(() => new IdentifierHasher([])).toThrow(RangeError);
    expect(() => new IdentifierHasher([pepper('v1', 'short')])).toThrow(
      RangeError,
    );
    expect(
      () =>
        new IdentifierHasher([pepper('v1', SECRET_1), pepper('v1', SECRET_2)]),
    ).toThrow(RangeError);
    expect(() => new IdentifierHasher([pepper('one', SECRET_1)])).toThrow(
      RangeError,
    );
  });

  it('keeps its own copy of the pepper', () => {
    const secret = Buffer.from(SECRET_1);
    const own = new IdentifierHasher([{ version: 'v1', secret }]);
    const before = own.hash('PAN', 'ABCDE1234F');
    secret.fill(0);
    expect(own.hash('PAN', 'ABCDE1234F')).toBe(before);
  });
});

describe('normalizeIdentifier', () => {
  it('reads a bare Indian mobile number as +91', () => {
    expect(normalizeIdentifier('PHONE', '98765 43210')).toBe('+919876543210');
  });
});

describe('parseIdentifierPeppers', () => {
  it('is null when unset or blank', () => {
    expect(parseIdentifierPeppers(undefined, 'X')).toBeNull();
    expect(parseIdentifierPeppers('  ', 'X')).toBeNull();
  });

  it('reads the list newest first', () => {
    const peppers = parseIdentifierPeppers(
      `v2:${SECRET_2}, v1:${SECRET_1}`,
      'IDENTIFIER_HASH_PEPPERS',
    );
    expect(peppers?.map((p) => p.version)).toEqual(['v2', 'v1']);
  });

  it('names the variable and entry but never the secret', () => {
    const attempt = () =>
      parseIdentifierPeppers(
        `v1:${SECRET_1},v2:tooshort`,
        'IDENTIFIER_HASH_PEPPERS',
      );
    expect(attempt).toThrow(/IDENTIFIER_HASH_PEPPERS/);
    try {
      attempt();
    } catch (error) {
      expect((error as Error).message).not.toContain('tooshort');
      expect((error as Error).message).not.toContain(SECRET_1);
    }
    expect(() => parseIdentifierPeppers(SECRET_1, 'X')).toThrow(/entry 1/);
  });
});
