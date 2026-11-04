import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { AgentSettingValidators } from '../adapters/platform/agent-platform.adapters';
import type { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import { AGENT_PROGRAM_SETTING_KEYS } from './agent-program-settings';
import {
  REFERRAL_SHARE_LINK_BASE_URL_KEY,
  referralShareLink,
  referralShareLinkBaseUrlProblem,
} from './agent-share-link';

const BASE = 'https://testapp.nenjammatrimony.com';
const PROBLEM =
  'Setting referral.share_link_base_url must be null or an https web address with no path, query or fragment (for example https://app.example.com), and must not contain "agent".';
const withBase = (base: unknown) => ({
  [REFERRAL_SHARE_LINK_BASE_URL_KEY]: base,
});

describe('referral.share_link_base_url', () => {
  it('is named as agreed and is not one of the parsed keys', () => {
    expect(REFERRAL_SHARE_LINK_BASE_URL_KEY).toBe(
      'referral.share_link_base_url',
    );
    expect(AGENT_PROGRAM_SETTING_KEYS).not.toContain(
      REFERRAL_SHARE_LINK_BASE_URL_KEY,
    );
  });

  describe('the validator', () => {
    it.each([
      null,
      BASE,
      'https://nenjammatrimony.com',
      'https://app.example.com:8443',
    ])('accepts %p', (value) => {
      expect(referralShareLinkBaseUrlProblem(value)).toBeNull();
    });

    it.each([
      // Not https.
      'http://testapp.nenjammatrimony.com',
      'ftp://testapp.nenjammatrimony.com',
      // A path (a trailing slash is one), a query or a fragment.
      `${BASE}/`,
      `${BASE}/join`,
      `${BASE}?x=1`,
      `${BASE}/?ref=`,
      `${BASE}#top`,
      // "agent", in any case and anywhere.
      'https://agent.nenjammatrimony.com',
      'https://AGENT.nenjammatrimony.com',
      'https://nenjam-Agent.example.com',
      'https://myagents.example.com',
      // Not written exactly as an origin.
      'https://TestApp.NenjamMatrimony.com',
      `${BASE}:443`,
      'https://user@testapp.nenjammatrimony.com',
      ` ${BASE}`,
      // Not a web address at all, or not a string.
      'testapp.nenjammatrimony.com',
      '',
      'https://',
      42,
      true,
      {},
      [],
    ])('refuses %p', (value) => {
      expect(referralShareLinkBaseUrlProblem(value)).toBe(PROBLEM);
    });

    it('is registered at startup', () => {
      const registered = new Map<string, (v: unknown) => string | null>();
      const settings = {
        registerValidator: (key: string, fn: (v: unknown) => string | null) =>
          registered.set(key, fn),
      } as unknown as PlatformSettingsService;
      new AgentSettingValidators(settings).onModuleInit();
      const fn = registered.get(REFERRAL_SHARE_LINK_BASE_URL_KEY);
      expect(fn?.(BASE)).toBeNull();
      expect(fn?.(null)).toBeNull();
      expect(fn?.('https://agent.example.com')).toBe(PROBLEM);
    });
  });

  describe('the link', () => {
    it('is {base}/?ref={code}', () => {
      expect(referralShareLink(withBase(BASE), 'NM7K2P9X')).toBe(
        'https://testapp.nenjammatrimony.com/?ref=NM7K2P9X',
      );
    });

    it('URL-encodes the code', () => {
      expect(referralShareLink(withBase(BASE), 'NM 7&K=2/P?#')).toBe(
        `${BASE}/?ref=NM%207%26K%3D2%2FP%3F%23`,
      );
    });

    it.each([
      ['missing', {}],
      ['null', withBase(null)],
      ['empty', withBase('')],
      ['not https', withBase('http://testapp.nenjammatrimony.com')],
      ['with a trailing slash', withBase(`${BASE}/`)],
      ['with a path', withBase(`${BASE}/join`)],
      ['containing "agent"', withBase('https://agent.example.com')],
      ['not a string', withBase(42)],
    ])('is null when the base is %s', (_, raw) => {
      expect(referralShareLink(raw, 'NM7K2P9X')).toBeNull();
    });

    it('is null when the code itself would put "agent" in it', () => {
      expect(referralShareLink(withBase(BASE), 'NMAGENT2')).toBeNull();
      expect(referralShareLink(withBase(BASE), 'NMaGeNt2')).toBeNull();
      expect(referralShareLink(withBase(BASE), 'NMAGEN2T')).toBe(
        `${BASE}/?ref=NMAGEN2T`,
      );
    });

    it('an inherited value does not count as set', () => {
      const raw = Object.create(withBase(BASE)) as Record<string, unknown>;
      expect(referralShareLink(raw, 'NM7K2P9X')).toBeNull();
    });
  });

  it('exactly one migration seeds it, as JSON null (no value), data only', () => {
    const dir = join(
      __dirname,
      '../../../../../../libs/database/prisma/migrations',
    );
    const folders = readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort();
    const seeding = folders.filter((name) =>
      readFileSync(join(dir, name, 'migration.sql'), 'utf8').includes(
        `'${REFERRAL_SHARE_LINK_BASE_URL_KEY}'`,
      ),
    );
    expect(seeding).toEqual(['20261104090000_agent_share_link_setting']);
    expect(seeding[0] > '20261103090200_agent_client_settings_seed').toBe(true);
    const sql = readFileSync(join(dir, seeding[0], 'migration.sql'), 'utf8');
    expect(sql).toContain(
      `('${REFERRAL_SHARE_LINK_BASE_URL_KEY}', 'null'::jsonb,`,
    );
    expect(sql).toContain(
      'INSERT INTO "platform_settings" ("key", "value", "description") VALUES',
    );
    expect(sql.trimEnd().endsWith('ON CONFLICT ("key") DO NOTHING;')).toBe(
      true,
    );
    expect(sql).not.toMatch(/^\s*(CREATE|ALTER|DROP|UPDATE|DELETE)\b/im);
    expect(sql.match(/^\s*\('/gm)).toHaveLength(1);
  });
});
