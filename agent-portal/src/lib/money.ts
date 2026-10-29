/** Paise → rupees, e.g. 50000 → "₹500.00" (the handoff's format). */
export function formatPaise(paise: number): string {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(paise / 100);
}

/** Basis points → percent text, e.g. 1000 → "10%". */
export function formatBasisPoints(bp: number): string {
  return `${bp / 100}%`;
}
