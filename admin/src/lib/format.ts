const rupees = new Intl.NumberFormat('en-IN', {
  style: 'currency',
  currency: 'INR',
  minimumFractionDigits: 0,
  maximumFractionDigits: 2,
});

/** 399900 → "₹3,999". Null → "Not priced". */
export function formatPaise(paise: number | null | undefined): string {
  if (paise === null || paise === undefined) return 'Not priced';
  return rupees.format(paise / 100);
}

/**
 * What an admin types in a rupee field → integer paise. Accepts "3999",
 * "3,999", "₹3,999.50"; returns null for blank and NaN for anything that is
 * not a positive amount with at most two decimals.
 */
export function rupeesToPaise(input: string): number | null {
  const cleaned = input.replace(/[₹,\s]/g, '');
  if (cleaned === '') return null;
  if (!/^\d+(\.\d{1,2})?$/.test(cleaned)) return Number.NaN;
  const [whole = '0', fraction = ''] = cleaned.split('.');
  const paise = Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
  return paise > 0 ? paise : Number.NaN;
}

/** 399950 → "3999.50"; 399900 → "3999". For prefilling rupee inputs. */
export function paiseToRupeesInput(paise: number | null): string {
  if (paise === null) return '';
  const whole = Math.trunc(paise / 100);
  const fraction = paise % 100;
  return fraction === 0 ? String(whole) : `${whole}.${String(fraction).padStart(2, '0')}`;
}

const dateTime = new Intl.DateTimeFormat('en-IN', {
  dateStyle: 'medium',
  timeStyle: 'short',
  timeZone: 'Asia/Kolkata',
});
const dateOnly = new Intl.DateTimeFormat('en-IN', {
  dateStyle: 'medium',
  timeZone: 'Asia/Kolkata',
});

/** Shown in IST, the timezone every business rule here uses. */
export function formatDateTime(iso: string | null | undefined): string {
  return iso ? dateTime.format(new Date(iso)) : '—';
}

export function formatDate(iso: string | null | undefined): string {
  return iso ? dateOnly.format(new Date(iso)) : '—';
}

/** "SUBSCRIPTION_GRANT" → "Subscription grant". */
export function humanize(value: string): string {
  const spaced = value.replace(/[._]/g, ' ').toLowerCase();
  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}
