import type { LocalizedText } from '../api/types';

/**
 * Picks the display text for a label from `GET /agent/config`. Tamil labels
 * are still `<to be supplied>`, so a missing or placeholder Tamil value falls
 * back to English rather than showing the placeholder or a guessed word. The
 * raw key is the last resort (a key the config doesn't cover yet).
 */
export function pickLabel(
  text: LocalizedText | undefined,
  key: string,
  lang: 'en' | 'ta' = 'en',
): string {
  if (!text) return key;
  const ta = text.ta?.trim();
  if (lang === 'ta' && ta && ta !== '<to be supplied>') return ta;
  return text.en || key;
}

/** True when a Tamil value is actually usable (not the pending placeholder). */
export function hasTamil(text: LocalizedText | undefined): boolean {
  const ta = text?.ta?.trim();
  return !!ta && ta !== '<to be supplied>';
}

type Tone = 'neutral' | 'success' | 'warning' | 'danger' | 'info';

/** Badge tone for an agent status. The label text always carries the meaning too. */
export function statusTone(status: string): Tone {
  switch (status) {
    case 'ACTIVE':
      return 'success';
    case 'PENDING_APPROVAL':
    case 'SUSPENDED':
      return 'warning';
    case 'REJECTED':
    case 'TERMINATED':
      return 'danger';
    default:
      return 'neutral';
  }
}

/** Tone for a commission/payout/stage key from the contract. */
export function moneyTone(key: string): Tone {
  switch (key) {
    case 'PAID':
    case 'PURCHASED':
      return 'success';
    case 'ON_HOLD':
    case 'CREATED':
    case 'PROFILE_COMPLETE':
      return 'warning';
    case 'APPROVED':
      return 'info';
    case 'CANCELLED':
      return 'danger';
    default:
      return 'neutral';
  }
}
