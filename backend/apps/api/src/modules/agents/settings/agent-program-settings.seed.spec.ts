import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { OTP_POLICY } from '../../platform/otp/otp.service';
import {
  AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
  AGENT_PROGRAM_SETTING_KEYS,
  parseAgentProgramSettings,
} from './agent-program-settings';

/**
 * The settings seed migrations, read as text: every row must be one of our
 * keys with a value our parser accepts, and together they must set all 18.
 */
const MIGRATIONS = join(
  __dirname,
  '../../../../../../libs/database/prisma/migrations',
);
const DECIDED = '20261029110200_agent_program_settings_seed';
const PROPOSED = '20261029110300_agent_program_settings_proposed';
const LAST_OF_155 = '20261029110100_agent_commission_policy_seed';

function sqlOf(folder: string): string {
  return readFileSync(join(MIGRATIONS, folder, 'migration.sql'), 'utf8');
}

/** Rows of `('key', 'json'::jsonb, 'description')`, comments stripped. */
function rowsOf(sql: string): Array<{ key: string; value: unknown }> {
  const code = sql
    .split('\n')
    .filter((line) => !line.trimStart().startsWith('--'))
    .join('\n');
  const rows = [
    ...code.matchAll(/\(\s*'([^']*)',\s*'((?:[^']|'')*)'::jsonb,/g),
  ];
  return rows.map(([, key, json]) => ({
    key,
    value: JSON.parse(json.replace(/''/g, "'")) as unknown,
  }));
}

const decided = rowsOf(sqlOf(DECIDED));
const proposed = rowsOf(sqlOf(PROPOSED));
const all = [...decided, ...proposed];

describe('agent-program settings seed migrations', () => {
  it('both sort after #155 and are the last agent migrations', () => {
    const folders = readdirSync(MIGRATIONS).filter((f) => /^\d{14}_/.test(f));
    expect(DECIDED > LAST_OF_155).toBe(true);
    expect(PROPOSED > DECIDED).toBe(true);
    expect(folders).toEqual(expect.arrayContaining([DECIDED, PROPOSED]));
  });

  it('seed exactly the decided values', () => {
    expect(Object.fromEntries(decided.map((r) => [r.key, r.value]))).toEqual({
      'commission.auto_approve': true,
      'commission.require_verified_profile': false,
      'referral.credit_window_days': 60,
      'referral.member_discount_bps': 500,
      'referral.discount_stacks_with_coupons': false,
      'referral.discount_only_in_credit_window': true,
      'payout.minimum_amount_paise': 50000,
      'agent.client_draft_limit': 10,
      'agent.payout_details_wait_hours': 72,
      'commission.base': 'AMOUNT_PAID_EXCLUDING_GST',
      'commission.base_provisional': false,
      'payout.tax_withholding': null,
    });
  });

  it('propose values for exactly the six undecided keys, in their own migration', () => {
    expect(proposed.map((r) => r.key).sort()).toEqual(
      [
        'agent.access_token_ttl_seconds',
        'agent.refresh_token_ttl_seconds',
        'agent.otp_resend_after_seconds',
        'referral.code_validation_ip_limit',
        'referral.code_validation_code_limit',
        'referral.code_validation_window_seconds',
      ].sort(),
    );
  });

  it('together set every one of the 18 keys once, and the parser accepts them all', () => {
    const keys = all.map((r) => r.key);
    expect(new Set(keys).size).toBe(keys.length);
    expect([...keys].sort()).toEqual([...AGENT_PROGRAM_SETTING_KEYS].sort());
    const parsed = parseAgentProgramSettings(
      Object.fromEntries(all.map((r) => [r.key, r.value])),
    );
    expect(parsed.missing).toEqual([]);
  });

  it('the OTP resend time is not shorter than the OTP service enforces', () => {
    const resend = all.find(
      (r) => r.key === AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
    );
    expect(resend?.value).toBeGreaterThanOrEqual(
      Math.ceil(OTP_POLICY.resendAfterMs / 1000),
    );
  });

  it.each([DECIDED, PROPOSED])(
    '%s follows the platform_settings seed format',
    (folder) => {
      const sql = sqlOf(folder);
      expect(sql).toContain(
        'INSERT INTO "platform_settings" ("key", "value", "description") VALUES',
      );
      expect(sql.trimEnd().endsWith('ON CONFLICT ("key") DO NOTHING;')).toBe(
        true,
      );
      // Data only: no schema statement, and never a SQL NULL value.
      expect(sql).not.toMatch(/^\s*(CREATE|ALTER|DROP|UPDATE|DELETE)\b/im);
      expect(sql).not.toMatch(/,\s*NULL\s*,/i);
      for (const { key } of rowsOf(sql)) {
        expect(key).toMatch(/^[a-z]+(\.[a-z_]+)+$/);
      }
      // Every row was read: one row per ('key', ...) tuple in the file.
      const tuples = sql.match(/^\s*\('/gm) ?? [];
      expect(rowsOf(sql)).toHaveLength(tuples.length);
    },
  );
});
