import { isPanVerified } from './pan-verification';

describe('isPanVerified', () => {
  it('is false until staff verify the PAN', () => {
    expect(isPanVerified({ panVerifiedAt: null })).toBe(false);
  });

  it('is true once panVerifiedAt is set', () => {
    expect(
      isPanVerified({ panVerifiedAt: new Date('2026-10-28T10:00:00Z') }),
    ).toBe(true);
  });
});
