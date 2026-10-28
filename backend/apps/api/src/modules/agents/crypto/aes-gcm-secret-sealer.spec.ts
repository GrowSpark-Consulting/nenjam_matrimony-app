import { AesGcmSecretSealer } from './aes-gcm-secret-sealer';

// Test-only keys, not secrets.
const KEY = Buffer.alloc(32, 1);
const OTHER_KEY = Buffer.alloc(32, 2);

describe('AesGcmSecretSealer', () => {
  const sealer = new AesGcmSecretSealer(KEY);

  it('opens what it sealed, including unicode and long text', () => {
    for (const text of [
      'ABCDE1234F',
      '+919876543210',
      'ரவி குமார்',
      'x'.repeat(5000),
    ]) {
      expect(sealer.open(sealer.seal(text))).toBe(text);
    }
  });

  it('uses a "v1:" prefix and base64url after it', () => {
    expect(sealer.seal('ABCDE1234F')).toMatch(/^v1:[A-Za-z0-9_-]+$/);
  });

  it('never contains the plaintext', () => {
    const sealed = sealer.seal('ABCDE1234F');
    expect(sealed).not.toContain('ABCDE1234F');
    expect(
      Buffer.from(sealed.slice(3), 'base64url').toString('latin1'),
    ).not.toContain('ABCDE1234F');
  });

  it('gives a different result every time (random IV)', () => {
    const results = new Set(
      Array.from({ length: 20 }, () => sealer.seal('same')),
    );
    expect(results.size).toBe(20);
  });

  it('rejects text altered after sealing', () => {
    const sealed = sealer.seal('ABCDE1234F');
    const raw = Buffer.from(sealed.slice(3), 'base64url');
    raw[raw.length - 1] ^= 1;
    expect(() => sealer.open(`v1:${raw.toString('base64url')}`)).toThrow(
      'The sealed value could not be opened.',
    );
  });

  it('rejects text sealed with another key', () => {
    const sealed = new AesGcmSecretSealer(OTHER_KEY).seal('ABCDE1234F');
    expect(() => sealer.open(sealed)).toThrow('could not be opened');
  });

  it.each(['', 'ABCDE1234F', 'v2:abc', 'v1:', 'v1:AAAA', 'v1:!!!!'])(
    'rejects the malformed value %p',
    (value) => {
      expect(() => sealer.open(value)).toThrow(Error);
    },
  );

  it('refuses to seal an empty or non-string value', () => {
    expect(() => sealer.seal('')).toThrow(RangeError);
    expect(() => sealer.seal(undefined as unknown as string)).toThrow(
      RangeError,
    );
  });

  it.each([0, 16, 31, 33, 64])('refuses a key of %p bytes', (size) => {
    expect(() => new AesGcmSecretSealer(Buffer.alloc(size, 1))).toThrow(
      RangeError,
    );
  });

  it('refuses a key that is not a Buffer', () => {
    expect(
      () => new AesGcmSecretSealer('x'.repeat(32) as unknown as Buffer),
    ).toThrow(RangeError);
  });

  it('keeps its own copy of the key', () => {
    const key = Buffer.alloc(32, 3);
    const own = new AesGcmSecretSealer(key);
    const sealed = own.seal('secret');
    key.fill(9);
    expect(own.open(sealed)).toBe('secret');
  });

  it('puts neither the plaintext nor the key in any error message', () => {
    const messages: string[] = [];
    const sealed = sealer.seal('ABCDE1234F');
    for (const attempt of [
      () => new AesGcmSecretSealer(Buffer.alloc(5, 1)),
      () => new AesGcmSecretSealer(OTHER_KEY).open(sealed),
      () => sealer.open('v1:AAAA'),
      () => sealer.open(`v1:${Buffer.alloc(40, 1).toString('base64url')}`),
    ]) {
      try {
        attempt();
      } catch (error) {
        messages.push((error as Error).message);
      }
    }
    expect(messages).toHaveLength(4);
    for (const message of messages) {
      expect(message).not.toContain('ABCDE1234F');
      expect(message).not.toContain(KEY.toString('hex'));
      expect(message).not.toContain(OTHER_KEY.toString('hex'));
    }
  });
});
