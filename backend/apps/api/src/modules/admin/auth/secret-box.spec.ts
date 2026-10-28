import {
  hashEnrollmentCode,
  hashOpaqueToken,
  newEnrollmentCode,
  newOpaqueToken,
} from './secret-box';

describe('secret-box', () => {
  it('issues unguessable tokens and stores only their hash', () => {
    const token = newOpaqueToken();
    expect(token).toMatch(/^[\w-]{43}$/);
    expect(hashOpaqueToken(token)).toMatch(/^[0-9a-f]{64}$/);
    expect(hashOpaqueToken(token)).not.toContain(token);
    expect(newOpaqueToken()).not.toBe(token);
  });

  it('issues readable enrolment codes whose hash ignores case, spaces and dashes', () => {
    const code = newEnrollmentCode();
    expect(code).toMatch(/^[2-9A-HJKMNP-Z]{5}-[2-9A-HJKMNP-Z]{5}$/);
    const typed = ` ${code.toLowerCase().replace('-', ' ')} `;
    expect(hashEnrollmentCode(typed)).toBe(hashEnrollmentCode(code));
    expect(hashEnrollmentCode('AAAAA-AAAAA')).not.toBe(
      hashEnrollmentCode(code),
    );
  });
});
