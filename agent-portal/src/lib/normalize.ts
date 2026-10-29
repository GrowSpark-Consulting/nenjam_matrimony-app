// Input clean-up before sending, exactly as the contract asks.

/** Removes spaces and hyphens (referral codes, bank account numbers). */
export function stripSpacesAndHyphens(value: string): string {
  return value.replace(/[\s-]+/g, '');
}

/** "98765 43210" or "+91 98765-43210" → "+919876543210". */
export function normalizeIndianPhone(value: string): string {
  const digits = value.replace(/\D/g, '');
  if (digits.length === 10) return `+91${digits}`;
  if (digits.length === 12 && digits.startsWith('91')) return `+${digits}`;
  return value.trim().startsWith('+') ? `+${digits}` : digits;
}

export const normalizePan = (v: string) => v.trim().toUpperCase();
export const normalizeIfsc = (v: string) => v.trim().toUpperCase();
export const normalizeUpi = (v: string) => v.trim().toLowerCase();
export const normalizeAccountNumber = (v: string) => stripSpacesAndHyphens(v.trim());

export const PAN_PATTERN = /^[A-Z]{5}[0-9]{4}[A-Z]$/;
export const UPI_PATTERN = /^[a-z0-9._-]{2,256}@[a-z][a-z0-9]{1,63}$/;
export const ACCOUNT_PATTERN = /^[0-9]{9,18}$/;
export const IFSC_PATTERN = /^[A-Z]{4}0[A-Z0-9]{6}$/;
export const PHONE_PATTERN = /^\+91[0-9]{10}$/;
