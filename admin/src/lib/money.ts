import type { CommissionStatus, PayoutIneligibleReason, PayoutStatus } from './types';

const COMMISSION_LABELS: Record<CommissionStatus, string> = {
  ON_HOLD: 'on hold',
  AWAITING_VERIFICATION: 'awaiting profile verification',
  IN_REVIEW: 'in review',
  FROZEN: 'frozen (agent paused or terminated)',
  READY: 'ready for approval',
  APPROVED: 'approved',
  PAID: 'paid',
  CANCELLED: 'cancelled',
  REVERSED: 'reversed by a refund',
};

export const COMMISSION_STATUSES = Object.keys(COMMISSION_LABELS) as CommissionStatus[];

export function commissionStatusLabel(status: CommissionStatus): string {
  return COMMISSION_LABELS[status] ?? status.toLowerCase();
}

/** Approve and cancel apply to a commission still being decided; an approved
 *  one can be cancelled too; a paid or closed one cannot change. The API
 *  makes the final call (409 on a wrong status). */
export function commissionActions(
  status: CommissionStatus,
): Array<'approve' | 'cancel' | 'override'> {
  switch (status) {
    case 'ON_HOLD':
    case 'AWAITING_VERIFICATION':
    case 'IN_REVIEW':
    case 'READY':
    case 'FROZEN':
      return ['approve', 'cancel', 'override'];
    case 'APPROVED':
      return ['cancel', 'override'];
    default:
      return [];
  }
}

const REASON_LABELS: Record<PayoutIneligibleReason, string> = {
  AGENT_NOT_PAYABLE: 'The agent is not active or paused for payouts',
  PAN_NOT_VERIFIED: 'PAN not verified',
  DETAILS_NOT_VERIFIED: 'Payout details not verified',
  WAIT_NOT_OVER: 'Payout details changed recently; still waiting',
  NOTHING_TO_PAY: 'Nothing approved to pay',
  BELOW_MINIMUM: 'Below the minimum payout',
  PAYOUT_EXISTS: 'A payout already exists for this period',
  TAX_RULE_UNSUPPORTED: 'Tax withholding is set but not supported yet',
  LEDGER_BALANCE_TOO_LOW: 'An earlier refund left too little balance',
};

export function payoutReasonLabel(reason: PayoutIneligibleReason): string {
  return REASON_LABELS[reason] ?? reason;
}

export function payoutStatusLabel(status: PayoutStatus): string {
  return status === 'CREATED' ? 'to be paid' : status.toLowerCase();
}

/** `YYYY-MM` for [date] in Indian time: the payout period a payment falls in. */
export function periodOf(date: Date): string {
  const ist = new Date(date.getTime() + 5.5 * 3600_000);
  return `${ist.getUTCFullYear()}-${String(ist.getUTCMonth() + 1).padStart(2, '0')}`;
}

/** The month before [date]'s: what is usually paid now. */
export function previousPeriod(date: Date): string {
  const ist = new Date(date.getTime() + 5.5 * 3600_000);
  ist.setUTCDate(1);
  ist.setUTCMonth(ist.getUTCMonth() - 1);
  return `${ist.getUTCFullYear()}-${String(ist.getUTCMonth() + 1).padStart(2, '0')}`;
}

export const PERIOD_PATTERN = /^\d{4}-(0[1-9]|1[0-2])$/;

/** 1000 basis points → "10%". */
export function formatBps(bps: number): string {
  return `${bps / 100}%`;
}
