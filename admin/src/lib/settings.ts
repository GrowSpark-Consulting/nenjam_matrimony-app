/**
 * Platform settings: business values the API reads on every request (rates,
 * limits, feature switches). Values are JSON; `null` means "not set". The
 * API validates each key's value again and refuses what that feature can't
 * use, so these helpers only turn what the admin typed into JSON.
 */

export interface PlatformSetting {
  key: string;
  value: unknown;
  description: string | null;
  version: number;
  updatedAt: string;
}

export interface SettingsResponse {
  items: PlatformSetting[];
}

/** How the edit form lets an admin type a value. */
export type SettingKind = 'boolean' | 'number' | 'text' | 'null' | 'json';

export const SETTING_KINDS: ReadonlyArray<{ kind: SettingKind; label: string }> = [
  { kind: 'boolean', label: 'On / off' },
  { kind: 'number', label: 'Number' },
  { kind: 'text', label: 'Text' },
  { kind: 'null', label: 'Not set' },
  { kind: 'json', label: 'JSON (advanced)' },
];

export function settingKindOf(value: unknown): SettingKind {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'boolean') return 'boolean';
  if (typeof value === 'number') return 'number';
  if (typeof value === 'string') return 'text';
  return 'json';
}

/** The text the edit form starts with for [value] shown as [kind]. */
export function settingInputText(kind: SettingKind, value: unknown): string {
  switch (kind) {
    case 'boolean':
      return value === true ? 'true' : 'false';
    case 'number':
      return typeof value === 'number' ? String(value) : '';
    case 'text':
      return typeof value === 'string' ? value : '';
    case 'null':
      return '';
    case 'json':
      return value === undefined ? '' : JSON.stringify(value, null, 2);
  }
}

export type ParsedSetting = { ok: true; value: unknown } | { ok: false; problem: string };

/** What the admin typed as [kind], as the JSON value to send. */
export function parseSettingInput(kind: SettingKind, raw: string): ParsedSetting {
  const text = raw.trim();
  switch (kind) {
    case 'boolean':
      if (text === 'true') return { ok: true, value: true };
      if (text === 'false') return { ok: true, value: false };
      return { ok: false, problem: 'Choose on or off.' };
    case 'number': {
      if (!/^-?\d+(\.\d+)?$/.test(text)) {
        return { ok: false, problem: 'Enter a number, for example 14 or 0.5.' };
      }
      return { ok: true, value: Number(text) };
    }
    case 'text':
      return text
        ? { ok: true, value: text }
        : { ok: false, problem: 'Enter the text, or choose “Not set”.' };
    case 'null':
      return { ok: true, value: null };
    case 'json':
      if (!text) return { ok: false, problem: 'Enter a JSON value, for example {"rate": 5}.' };
      try {
        return { ok: true, value: JSON.parse(text) as unknown };
      } catch {
        return { ok: false, problem: 'That isn’t valid JSON.' };
      }
  }
}

/** Same JSON value (key order matters, as the API stores what it is sent). */
export function sameSettingValue(a: unknown, b: unknown): boolean {
  return JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
}

/** A short readable form of a stored value for tables and dialogs. */
export function formatSettingValue(value: unknown): string {
  if (value === null || value === undefined) return 'not set';
  if (typeof value === 'boolean') return value ? 'on (true)' : 'off (false)';
  if (typeof value === 'string') return value;
  return JSON.stringify(value);
}

const GROUP_NAMES: Record<string, string> = {
  agent: 'Agent program',
  commission: 'Commissions',
  payment: 'Payments',
  payout: 'Payouts',
  referral: 'Referrals',
};

/** Settings grouped by the part of the key before the first dot, keys sorted. */
export function groupSettings(
  items: readonly PlatformSetting[],
): Array<{ group: string; title: string; items: PlatformSetting[] }> {
  const groups = new Map<string, PlatformSetting[]>();
  for (const item of [...items].sort((a, b) => a.key.localeCompare(b.key))) {
    const group = item.key.includes('.') ? item.key.slice(0, item.key.indexOf('.')) : 'other';
    groups.set(group, [...(groups.get(group) ?? []), item]);
  }
  return [...groups.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([group, list]) => ({ group, title: GROUP_NAMES[group] ?? group, items: list }));
}
