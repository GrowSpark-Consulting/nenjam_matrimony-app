import {
  buildAdjustmentEntry,
  buildCreditEntry,
  buildPayoutDebitEntry,
  buildPayoutReleaseEntry,
  buildReversalEntry,
  CreditEntryInput,
  sumLedgerBalance,
} from './ledger-entries';

const credit = (overrides: Partial<CreditEntryInput> = {}) =>
  buildCreditEntry({
    agentId: 'agent-1',
    commissionId: 'comm-1',
    amountPaise: 10_000,
    calcType: 'PERCENTAGE',
    value: 1000,
    ruleSnapshot: { policyVersion: 3 },
    ...overrides,
  });

describe('buildCreditEntry', () => {
  it('is a positive CREDIT keyed on the commission, with the rule snapshot', () => {
    expect(credit()).toEqual({
      agentId: 'agent-1',
      type: 'CREDIT',
      amountPaise: 10_000,
      idempotencyKey: 'credit:comm-1',
      commissionId: 'comm-1',
      refundId: null,
      payoutId: null,
      calcType: 'PERCENTAGE',
      value: 1000,
      ruleSnapshot: { policyVersion: 3 },
      reason: null,
    });
  });

  it('stores a missing snapshot as null', () => {
    expect(credit({ ruleSnapshot: undefined }).ruleSnapshot).toBeNull();
  });

  it.each([0, -1, 1.5, NaN, Infinity])(
    'rejects amountPaise %p',
    (amountPaise) => {
      expect(() => credit({ amountPaise })).toThrow(RangeError);
    },
  );

  it.each([-1, 1.5, NaN])('rejects value %p', (value) => {
    expect(() => credit({ value })).toThrow(RangeError);
  });

  it.each([
    ['agentId', { agentId: '' }],
    ['agentId (blank)', { agentId: '   ' }],
    ['commissionId', { commissionId: '' }],
    ['calcType', { calcType: '' }],
  ])('rejects an empty %s', (_label, overrides) => {
    expect(() => credit(overrides)).toThrow(RangeError);
  });
});

describe('buildReversalEntry', () => {
  const reversal = (reversalPaise = 2_500, refundId = 'refund-1') =>
    buildReversalEntry({
      agentId: 'agent-1',
      commissionId: 'comm-1',
      refundId,
      reversalPaise,
    });

  it('is a NEGATIVE REVERSAL keyed on the refund', () => {
    expect(reversal()).toEqual({
      agentId: 'agent-1',
      type: 'REVERSAL',
      amountPaise: -2_500,
      idempotencyKey: 'reversal:refund-1',
      commissionId: 'comm-1',
      refundId: 'refund-1',
      payoutId: null,
      calcType: null,
      value: null,
      ruleSnapshot: null,
      reason: null,
    });
  });

  it('two refunds on one commission get two different keys', () => {
    expect(reversal(100, 'refund-1').idempotencyKey).not.toBe(
      reversal(100, 'refund-2').idempotencyKey,
    );
  });

  it.each([0, -2_500, 1.5, NaN])(
    'rejects reversalPaise %p (pass the magnitude; the builder applies the sign)',
    (value) => {
      expect(() => reversal(value)).toThrow(RangeError);
    },
  );

  it('rejects an empty refundId', () => {
    expect(() => reversal(100, '')).toThrow(RangeError);
  });
});

describe('payout entries', () => {
  const input = {
    agentId: 'agent-1',
    payoutId: 'payout-1',
    amountPaise: 60_000,
  };

  it('PAYOUT_DEBIT is negative and keyed on the payout', () => {
    expect(buildPayoutDebitEntry(input)).toMatchObject({
      type: 'PAYOUT_DEBIT',
      amountPaise: -60_000,
      idempotencyKey: 'payout:payout-1',
      payoutId: 'payout-1',
      commissionId: null,
    });
  });

  it('PAYOUT_RELEASE is positive with its own key', () => {
    expect(buildPayoutReleaseEntry(input)).toMatchObject({
      type: 'PAYOUT_RELEASE',
      amountPaise: 60_000,
      idempotencyKey: 'payout-release:payout-1',
      payoutId: 'payout-1',
    });
  });

  it('the debit and release of one payout never share a key', () => {
    expect(buildPayoutDebitEntry(input).idempotencyKey).not.toBe(
      buildPayoutReleaseEntry(input).idempotencyKey,
    );
  });

  it.each([0, -1, 1.5])('both reject amountPaise %p', (amountPaise) => {
    expect(() => buildPayoutDebitEntry({ ...input, amountPaise })).toThrow(
      RangeError,
    );
    expect(() => buildPayoutReleaseEntry({ ...input, amountPaise })).toThrow(
      RangeError,
    );
  });

  it('both reject an empty payoutId', () => {
    expect(() => buildPayoutDebitEntry({ ...input, payoutId: '' })).toThrow(
      RangeError,
    );
    expect(() => buildPayoutReleaseEntry({ ...input, payoutId: '' })).toThrow(
      RangeError,
    );
  });
});

describe('buildAdjustmentEntry', () => {
  const adjust = (
    overrides: Partial<Parameters<typeof buildAdjustmentEntry>[0]> = {},
  ) =>
    buildAdjustmentEntry({
      agentId: 'agent-1',
      amountPaise: 500,
      reason: 'Goodwill for delayed payout',
      idempotencyKey: 'adjustment:ticket-42',
      ...overrides,
    });

  it('keeps a positive amount, the reason and the caller key', () => {
    expect(adjust()).toEqual({
      agentId: 'agent-1',
      type: 'ADJUSTMENT',
      amountPaise: 500,
      idempotencyKey: 'adjustment:ticket-42',
      commissionId: null,
      refundId: null,
      payoutId: null,
      calcType: null,
      value: null,
      ruleSnapshot: null,
      reason: 'Goodwill for delayed payout',
    });
  });

  it('keeps a negative amount as given', () => {
    expect(adjust({ amountPaise: -300 }).amountPaise).toBe(-300);
  });

  it('trims the reason', () => {
    expect(adjust({ reason: '  Duplicate credit  ' }).reason).toBe(
      'Duplicate credit',
    );
  });

  it.each(['', '   '])('requires a reason (%p)', (reason) => {
    expect(() => adjust({ reason })).toThrow(RangeError);
  });

  it('requires a reason even when it is not a string', () => {
    expect(() => adjust({ reason: undefined as unknown as string })).toThrow(
      RangeError,
    );
  });

  it.each([0, 1.5, NaN, Infinity])('rejects amountPaise %p', (amountPaise) => {
    expect(() => adjust({ amountPaise })).toThrow(RangeError);
  });

  it('requires an idempotency key', () => {
    expect(() => adjust({ idempotencyKey: '' })).toThrow(RangeError);
  });
});

describe('sumLedgerBalance', () => {
  it('is 0 for no entries', () => {
    expect(sumLedgerBalance([])).toBe(0);
  });

  it('credit + reversal + payout debit + release', () => {
    const entries = [
      credit({ commissionId: 'c1', amountPaise: 10_000 }),
      credit({ commissionId: 'c2', amountPaise: 60_000 }),
      buildReversalEntry({
        agentId: 'agent-1',
        commissionId: 'c1',
        refundId: 'r1',
        reversalPaise: 2_500,
      }),
    ];
    expect(sumLedgerBalance(entries)).toBe(67_500);

    const debit = buildPayoutDebitEntry({
      agentId: 'agent-1',
      payoutId: 'p1',
      amountPaise: 67_500,
    });
    expect(sumLedgerBalance([...entries, debit])).toBe(0);

    const release = buildPayoutReleaseEntry({
      agentId: 'agent-1',
      payoutId: 'p1',
      amountPaise: 67_500,
    });
    expect(sumLedgerBalance([...entries, debit, release])).toBe(67_500);
  });

  it('can go negative when a reversal follows a paid payout', () => {
    expect(
      sumLedgerBalance([
        credit({ amountPaise: 10_000 }),
        buildPayoutDebitEntry({
          agentId: 'agent-1',
          payoutId: 'p1',
          amountPaise: 10_000,
        }),
        buildReversalEntry({
          agentId: 'agent-1',
          commissionId: 'comm-1',
          refundId: 'r1',
          reversalPaise: 10_000,
        }),
      ]),
    ).toBe(-10_000);
  });

  it('includes signed adjustments', () => {
    expect(
      sumLedgerBalance([
        credit({ amountPaise: 1_000 }),
        buildAdjustmentEntry({
          agentId: 'agent-1',
          amountPaise: -250,
          reason: 'Correction',
          idempotencyKey: 'adj-1',
        }),
      ]),
    ).toBe(750);
  });

  it('is exact where floating point would drift', () => {
    const big = Number.MAX_SAFE_INTEGER - 10;
    expect(
      sumLedgerBalance([
        { amountPaise: big },
        { amountPaise: 10 },
        { amountPaise: -5 },
      ]),
    ).toBe(Number.MAX_SAFE_INTEGER - 5);
  });

  it('allows intermediate totals beyond the safe range when the result fits', () => {
    expect(
      sumLedgerBalance([
        { amountPaise: Number.MAX_SAFE_INTEGER },
        { amountPaise: Number.MAX_SAFE_INTEGER },
        { amountPaise: -Number.MAX_SAFE_INTEGER },
      ]),
    ).toBe(Number.MAX_SAFE_INTEGER);
  });

  it('throws when the total leaves the safe integer range', () => {
    expect(() =>
      sumLedgerBalance([
        { amountPaise: Number.MAX_SAFE_INTEGER },
        { amountPaise: 1 },
      ]),
    ).toThrow(RangeError);
    expect(() =>
      sumLedgerBalance([
        { amountPaise: Number.MIN_SAFE_INTEGER },
        { amountPaise: -1 },
      ]),
    ).toThrow(RangeError);
  });

  it.each([1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1])(
    'throws on a non-integer amount %p',
    (amountPaise) => {
      expect(() => sumLedgerBalance([{ amountPaise }])).toThrow(RangeError);
    },
  );
});
