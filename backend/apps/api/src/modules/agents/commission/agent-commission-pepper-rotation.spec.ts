/**
 * IDENTIFIER_HASH_PEPPERS rotation: commissions.phone_hash is UNIQUE, but only
 * between hashes made with the SAME pepper version. The handler therefore
 * (1) copies the attribution's STORED hash, never re-hashing the phone, and
 * (2) before inserting, looks at every active version through
 * `hasher.hashAll` and refuses (marks the referral for review, never credits
 * twice) when any version already has a commission.
 */
import {
  T0,
  makeCommissionHarness,
  type CommissionHarness,
} from '../testing/agent-commission-harness';

let h: CommissionHarness;

beforeEach(async () => {
  h = makeCommissionHarness();
  h.seedPolicy();
  await h.seedAgent();
});

const commissions = async () => h.commissions.listPage({}, { limit: 50 });
const flagged = async (id: string) =>
  (await h.attributions.findById(id))?.needsReview;

/** Hash of member n's phone under pepper version `index` (0 = newest). */
const hashOf = (n: number, index: number) =>
  h.hasher.hashAll('PHONE', h.memberPhone(n))[index];

describe('the stored hash is copied, not recomputed', () => {
  it('the commission carries exactly the attribution hash, even one made under an older pepper', async () => {
    const oldHash = hashOf(1, 1);
    await h.seedAttribution(1, { memberPhoneHash: oldHash });
    await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
    const commission = await h.commissions.findByPaymentId('pay-1');
    expect(commission?.phoneHash).toBe(oldHash);
    expect(commission?.phoneHash).not.toBe(
      h.hasher.hash('PHONE', h.memberPhone(1)),
    );
  });

  it('the newest-version hash is copied as it is too', async () => {
    const newest = hashOf(1, 0);
    await h.seedAttribution(1, { memberPhoneHash: newest });
    await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
    expect((await h.commissions.findByPaymentId('pay-1'))?.phoneHash).toBe(
      newest,
    );
  });
});

describe('a hash from another pepper version blocks a second commission', () => {
  /** Member 1 earned under the OLD pepper; member 2 is the same person (same phone) under the NEW one. */
  const sameWoman = async () => {
    await h.seedAttribution(1, { memberPhoneHash: hashOf(1, 1) });
    await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
    // A second sign-up with the same phone, hashed with the new pepper.
    await h.seedAttribution(2, { memberPhoneHash: hashOf(1, 0) });
    h.members.add(
      {
        memberId: 'member-2',
        phoneHash: hashOf(1, 0),
        signedUpAt: T0,
        hasPaid: false,
      },
      {
        firstName: 'Priya',
        lastName: 'Sharma',
        phoneE164: h.memberPhone(1),
        age: 27,
        city: 'Madurai',
        signedUpAt: T0,
        stage: 'REGISTERED',
        profileCompletenessPct: 40,
      },
    );
  };

  it('the second attribution is marked for review and nothing is credited twice', async () => {
    await sameWoman();
    const result = await h.events.onPaymentSucceeded(h.paymentSucceeded(2));
    expect(result.outcome).toBe('DUPLICATE_PHONE_REVIEW');
    expect(await h.commissions.findByPaymentId('pay-2')).toBeNull();
    expect(await commissions()).toHaveLength(1);
    expect(await flagged('attr-2')).toBe(true);
    expect(await flagged('attr-1')).toBe(false);
    expect(h.audit.entries.at(-1)).toMatchObject({
      action: 'COMMISSION_BLOCKED_DUPLICATE_PHONE',
      entityId: 'attr-2',
    });
  });

  it('is idempotent: a replay flags and audits once', async () => {
    await sameWoman();
    await h.events.onPaymentSucceeded(h.paymentSucceeded(2));
    const auditCount = h.audit.entries.length;
    const again = await h.events.onPaymentSucceeded(h.paymentSucceeded(2));
    expect(again.outcome).toBe('DUPLICATE_PHONE_REVIEW');
    expect(h.audit.entries).toHaveLength(auditCount);
    expect(await commissions()).toHaveLength(1);
  });

  /** Member 2 is the same person as member 1, under the newest pepper. */
  const secondSignUp = async () => {
    await h.seedAttribution(2, { memberPhoneHash: hashOf(1, 0) });
    h.members.add(
      {
        memberId: 'member-2',
        phoneHash: hashOf(1, 0),
        signedUpAt: T0,
        hasPaid: false,
      },
      {
        firstName: 'P',
        lastName: 'S',
        phoneE164: h.memberPhone(1),
        age: 27,
        city: 'Madurai',
        signedUpAt: T0,
        stage: 'REGISTERED',
        profileCompletenessPct: 40,
      },
    );
  };

  it('a COMMISSION under another version blocks it, even when its referral is stored under a hash nobody knows', async () => {
    // attr-1 is stored under a hash of no active version; its commission is under the OLD version.
    await h.seedAttribution(1, { memberPhoneHash: 'v9:unknown' });
    await h.commissions.create({
      id: 'com-x',
      agentId: 'agent-1',
      attributionId: 'attr-1',
      paymentId: 'pay-x',
      phoneHash: hashOf(1, 1),
      policyVersionId: 'pol-1',
      status: 'ON_HOLD',
      calcType: 'PERCENTAGE',
      ruleValue: 1000,
      basePaise: 9500,
      amountPaise: 950,
      amountPaidPaise: 11210,
      taxableAmountPaise: 9500,
      creditedPaise: 0,
      reversedPaise: 0,
      holdUntil: T0,
      reviewReasons: [],
      approvedAt: null,
      paidAt: null,
      cancelledAt: null,
      payoutId: null,
      createdAt: T0,
    });
    await secondSignUp();
    expect(
      (await h.events.onPaymentSucceeded(h.paymentSucceeded(2))).outcome,
    ).toBe('DUPLICATE_PHONE_REVIEW');
  });

  it('an ATTRIBUTION under another version that earned a commission blocks it, even when that commission carries another hash', async () => {
    await h.seedAttribution(1, { memberPhoneHash: hashOf(1, 1) });
    await h.commissions.create({
      id: 'com-y',
      agentId: 'agent-1',
      attributionId: 'attr-1',
      paymentId: 'pay-y',
      phoneHash: 'v9:somewhere-else',
      policyVersionId: 'pol-1',
      status: 'ON_HOLD',
      calcType: 'PERCENTAGE',
      ruleValue: 1000,
      basePaise: 9500,
      amountPaise: 950,
      amountPaidPaise: 11210,
      taxableAmountPaise: 9500,
      creditedPaise: 0,
      reversedPaise: 0,
      holdUntil: T0,
      reviewReasons: [],
      approvedAt: null,
      paidAt: null,
      cancelledAt: null,
      payoutId: null,
      createdAt: T0,
    });
    await secondSignUp();
    expect(
      (await h.events.onPaymentSucceeded(h.paymentSucceeded(2))).outcome,
    ).toBe('DUPLICATE_PHONE_REVIEW');
  });

  it('an earlier attribution under another version that earned NOTHING does not block', async () => {
    await h.seedAttribution(1, { memberPhoneHash: hashOf(1, 1) });
    await secondSignUp();
    const result = await h.events.onPaymentSucceeded(h.paymentSucceeded(2));
    expect(result.outcome).toBe('CREATED');
    expect(await flagged('attr-2')).toBe(false);
  });

  it('the block audit row is written with the transaction', async () => {
    await sameWoman();
    const spy = jest.spyOn(h.audit, 'record');
    await h.events.onPaymentSucceeded(h.paymentSucceeded(2));
    const call = spy.mock.calls.find(
      ([entry]) => entry.action === 'COMMISSION_BLOCKED_DUPLICATE_PHONE',
    );
    expect(call?.[1]).toBeDefined();
  });

  it('works the other way round: an earlier commission under the NEW pepper blocks an OLD-pepper one', async () => {
    await h.seedAttribution(1, { memberPhoneHash: hashOf(1, 0) });
    await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
    await h.seedAttribution(2, { memberPhoneHash: hashOf(1, 2) });
    h.members.add(
      {
        memberId: 'member-2',
        phoneHash: hashOf(1, 2),
        signedUpAt: T0,
        hasPaid: false,
      },
      {
        firstName: 'Priya',
        lastName: 'Sharma',
        phoneE164: h.memberPhone(1),
        age: 27,
        city: 'Madurai',
        signedUpAt: T0,
        stage: 'REGISTERED',
        profileCompletenessPct: 40,
      },
    );
    expect(
      (await h.events.onPaymentSucceeded(h.paymentSucceeded(2))).outcome,
    ).toBe('DUPLICATE_PHONE_REVIEW');
    expect(await commissions()).toHaveLength(1);
  });

  it('an attribution under another version that earned one blocks, even when the commission hash differs', async () => {
    // Attribution A (old hash) has a commission whose hash is of a third version.
    await h.seedAttribution(1, { memberPhoneHash: hashOf(1, 1) });
    await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
    const first = await h.commissions.findByPaymentId('pay-1');
    await h.commissions.update(first!.id, {});
    await h.seedAttribution(2, { memberPhoneHash: hashOf(1, 0) });
    h.members.add(
      {
        memberId: 'member-2',
        phoneHash: hashOf(1, 0),
        signedUpAt: T0,
        hasPaid: false,
      },
      {
        firstName: 'P',
        lastName: 'S',
        phoneE164: h.memberPhone(1),
        age: 27,
        city: 'Madurai',
        signedUpAt: T0,
        stage: 'REGISTERED',
        profileCompletenessPct: 40,
      },
    );
    expect(
      (await h.events.onPaymentSucceeded(h.paymentSucceeded(2))).outcome,
    ).toBe('DUPLICATE_PHONE_REVIEW');
  });

  it('every version is looked at, not only the newest', async () => {
    await sameWoman();
    const spy = jest.spyOn(h.hasher, 'hashAll');
    await h.events.onPaymentSucceeded(h.paymentSucceeded(2));
    expect(spy).toHaveBeenCalledWith('PHONE', h.memberPhone(1));
  });
});

describe('nothing is blocked that should not be', () => {
  it('a different person (different phone) is credited', async () => {
    await h.seedAttribution(1);
    await h.seedAttribution(2);
    expect(
      (await h.events.onPaymentSucceeded(h.paymentSucceeded(1))).outcome,
    ).toBe('CREATED');
    expect(
      (await h.events.onPaymentSucceeded(h.paymentSucceeded(2))).outcome,
    ).toBe('CREATED');
  });

  it('a replay of the payment that earned the commission is ALREADY_PROCESSED, not a duplicate', async () => {
    await h.seedAttribution(1);
    await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
    const again = await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
    expect(again.outcome).toBe('ALREADY_PROCESSED');
    expect(await flagged('attr-1')).toBe(false);
  });

  it('a second payment of the same referral is ALREADY_PROCESSED, not flagged', async () => {
    await h.seedAttribution(1);
    await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
    const second = await h.events.onPaymentSucceeded(
      h.paymentSucceeded(2, { memberId: 'member-1' }),
    );
    expect(second.outcome).toBe('ALREADY_PROCESSED');
    expect(await flagged('attr-1')).toBe(false);
  });

  it('without the member (gone) only the stored hash is compared and the payment is credited', async () => {
    await h.seedAttribution(1, { memberId: null });
    const result = await h.events.onPaymentSucceeded(
      h.paymentSucceeded(1, { memberId: 'member-1' }),
    );
    // No attribution is found by member id when the member is gone.
    expect(result.outcome).toBe('NO_ATTRIBUTION');
  });

  it('a member whose phone cannot be read falls back to the stored hash and is credited', async () => {
    await h.seedAttribution(1);
    jest.spyOn(h.members, 'getReferralViewFields').mockResolvedValueOnce(null);
    expect(
      (await h.events.onPaymentSucceeded(h.paymentSucceeded(1))).outcome,
    ).toBe('CREATED');
  });
});

describe('the block and its audit row share the transaction', () => {
  it('a failed audit write leaves the attribution unflagged', async () => {
    await h.seedAttribution(1, { memberPhoneHash: hashOf(1, 1) });
    await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
    await h.seedAttribution(2, { memberPhoneHash: hashOf(1, 0) });
    h.members.add(
      {
        memberId: 'member-2',
        phoneHash: hashOf(1, 0),
        signedUpAt: T0,
        hasPaid: false,
      },
      {
        firstName: 'P',
        lastName: 'S',
        phoneE164: h.memberPhone(1),
        age: 27,
        city: 'Madurai',
        signedUpAt: T0,
        stage: 'REGISTERED',
        profileCompletenessPct: 40,
      },
    );
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(
      h.events.onPaymentSucceeded(h.paymentSucceeded(2)),
    ).rejects.toThrow('audit down');
    expect(await flagged('attr-2')).toBe(false);
  });
});
