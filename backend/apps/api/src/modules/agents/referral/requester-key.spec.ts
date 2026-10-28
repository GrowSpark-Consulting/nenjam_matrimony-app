import { looksLikeRawIp } from './requester-key';

describe('looksLikeRawIp', () => {
  it.each([
    '1.2.3.4',
    '255.255.255.255',
    '::1',
    '2401:4900:1c0a:2f3d::1',
    'requester:1.2.3.4',
    'ip:10.0.0.1',
    'requester:::1',
  ])('recognises the raw address %p', (key) => {
    expect(looksLikeRawIp(key)).toBe(true);
  });

  it.each([
    'v1:3f5a9c0d2b7e4a118c6d5f0e9a3b7c24',
    'hashed-a',
    'k-1',
    '1.2.3',
    '999.1.1.1',
    'user:member-1',
    'requester:v1:abcdef',
    '',
  ])('accepts the opaque key %p', (key) => {
    expect(looksLikeRawIp(key)).toBe(false);
  });
});
