import { withSafetyExclusions } from './safety-exclusions.builder';

describe('withSafetyExclusions', () => {
  it('appends the safety clauses to an existing AND array without dropping the originals', () => {
    const base = { AND: [{ userId: { not: 'me' } }] };
    const result = withSafetyExclusions(base, 'me');
    const and = result.AND as Record<string, unknown>[];

    expect(and[0]).toEqual({ userId: { not: 'me' } });
    expect(and.length).toBeGreaterThan(1);
  });

  it('excludes suspended/deactivated/banned users but not PENDING_VERIFICATION', () => {
    const and = withSafetyExclusions({ AND: [] }, 'me').AND as Record<
      string,
      unknown
    >[];
    expect(and).toContainEqual({
      user: {
        is: { status: { notIn: ['SUSPENDED', 'DEACTIVATED', 'BANNED'] } },
      },
    });
  });

  it('excludes both directions of a block', () => {
    const and = withSafetyExclusions({ AND: [] }, 'me').AND as Record<
      string,
      unknown
    >[];
    expect(and).toContainEqual({
      user: { is: { blocksMade: { none: { blockedUserId: 'me' } } } },
    });
    expect(and).toContainEqual({
      user: { is: { blocksReceived: { none: { blockerId: 'me' } } } },
    });
  });

  it('excludes both directions of a declined interest', () => {
    const and = withSafetyExclusions({ AND: [] }, 'me').AND as Record<
      string,
      unknown
    >[];
    expect(and).toContainEqual({
      user: {
        is: {
          receivedInterests: { none: { senderId: 'me', status: 'DECLINED' } },
        },
      },
    });
    expect(and).toContainEqual({
      user: {
        is: {
          sentInterests: { none: { receiverId: 'me', status: 'DECLINED' } },
        },
      },
    });
  });

  it('handles a WHERE with no AND array (treats as empty)', () => {
    const result = withSafetyExclusions({}, 'me');
    expect(Array.isArray(result.AND)).toBe(true);
  });
});
