import { IST_OFFSET_MS } from '../referral/agent-referral-view';

/** The calendar date in Indian time, "YYYY-MM-DD". Throws on an invalid date. */
export function toIstDate(value: Date): string {
  if (!(value instanceof Date) || Number.isNaN(value.getTime())) {
    throw new RangeError('Invalid date.');
  }
  return new Date(value.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
}
