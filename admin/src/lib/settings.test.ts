import { describe, expect, it } from 'vitest';
import { visibleNav } from './permissions';
import {
  formatSettingValue,
  groupSettings,
  parseSettingInput,
  sameSettingValue,
  settingInputText,
  settingKindOf,
  type PlatformSetting,
} from './settings';

const setting = (key: string, value: unknown): PlatformSetting => ({
  key,
  value,
  description: null,
  version: 1,
  updatedAt: '2026-11-04T10:00:00.000Z',
});

describe('settings: reading the stored value', () => {
  it('picks the form for each kind of value', () => {
    expect(settingKindOf(false)).toBe('boolean');
    expect(settingKindOf(14)).toBe('number');
    expect(settingKindOf('AMOUNT_PAID_EXCLUDING_GST')).toBe('text');
    expect(settingKindOf(null)).toBe('null');
    expect(settingKindOf({ rate: 5 })).toBe('json');
    expect(settingKindOf([1, 2])).toBe('json');
  });

  it('starts the form with the current value', () => {
    expect(settingInputText('boolean', true)).toBe('true');
    expect(settingInputText('boolean', null)).toBe('false');
    expect(settingInputText('number', 500)).toBe('500');
    expect(settingInputText('text', 'https://app.example.com')).toBe('https://app.example.com');
    expect(settingInputText('text', null)).toBe('');
    expect(settingInputText('json', { a: 1 })).toBe('{\n  "a": 1\n}');
  });

  it('shows values readably', () => {
    expect(formatSettingValue(true)).toBe('on (true)');
    expect(formatSettingValue(false)).toBe('off (false)');
    expect(formatSettingValue(null)).toBe('not set');
    expect(formatSettingValue(50000)).toBe('50000');
    expect(formatSettingValue('https://x.example')).toBe('https://x.example');
    expect(formatSettingValue({ a: 1 })).toBe('{"a":1}');
  });
});

describe('settings: turning what was typed into JSON', () => {
  it('reads on/off as booleans only', () => {
    expect(parseSettingInput('boolean', 'true')).toEqual({ ok: true, value: true });
    expect(parseSettingInput('boolean', 'false')).toEqual({ ok: true, value: false });
    expect(parseSettingInput('boolean', 'yes').ok).toBe(false);
  });

  it('reads plain numbers and refuses anything else', () => {
    expect(parseSettingInput('number', ' 14 ')).toEqual({ ok: true, value: 14 });
    expect(parseSettingInput('number', '0.5')).toEqual({ ok: true, value: 0.5 });
    expect(parseSettingInput('number', '-3')).toEqual({ ok: true, value: -3 });
    for (const bad of ['', '1e3', '12abc', '1,000', 'NaN', 'Infinity', '.5']) {
      expect(parseSettingInput('number', bad).ok).toBe(false);
    }
  });

  it('trims text and refuses empty text (use "Not set" instead)', () => {
    expect(parseSettingInput('text', ' https://app.example.com ')).toEqual({
      ok: true,
      value: 'https://app.example.com',
    });
    expect(parseSettingInput('text', '   ').ok).toBe(false);
  });

  it('sends null for "Not set" whatever was typed', () => {
    expect(parseSettingInput('null', 'anything')).toEqual({ ok: true, value: null });
  });

  it('parses JSON and reports invalid JSON', () => {
    expect(parseSettingInput('json', '{"rate": 5}')).toEqual({ ok: true, value: { rate: 5 } });
    expect(parseSettingInput('json', 'null')).toEqual({ ok: true, value: null });
    expect(parseSettingInput('json', '{rate: 5}').ok).toBe(false);
    expect(parseSettingInput('json', '').ok).toBe(false);
  });

  it('notices when nothing would change', () => {
    expect(sameSettingValue(false, false)).toBe(true);
    expect(sameSettingValue(null, undefined)).toBe(true);
    expect(sameSettingValue(14, '14')).toBe(false);
    expect(sameSettingValue({ a: 1 }, { a: 1 })).toBe(true);
  });
});

describe('settings: navigation', () => {
  it('shows the Settings section to admins who can view settings', () => {
    expect(visibleNav(['system.view']).map((n) => n.href)).toEqual(['/settings/']);
    expect(visibleNav(['config.edit']).map((n) => n.href)).toEqual([]);
  });
});

describe('settings: grouping', () => {
  it('groups by key prefix with readable titles, sorted', () => {
    const groups = groupSettings([
      setting('referral.share_link_base_url', null),
      setting('agent.clients_enabled', false),
      setting('payment.gst_rate_bps', 0),
      setting('agent.client_draft_limit', 10),
      setting('standalone', 1),
    ]);
    expect(groups.map((g) => g.title)).toEqual([
      'Agent program',
      'other',
      'Payments',
      'Referrals',
    ]);
    expect(groups[0]?.items.map((s) => s.key)).toEqual([
      'agent.client_draft_limit',
      'agent.clients_enabled',
    ]);
  });
});
