import { AGENT_CONTENT, StaticAgentContent } from '../content/agent-content';
import { renderShareMessage } from '../referral/render-share-message';
import {
  AGENT_CLIENT_DRAFT_LIMIT_KEY,
  COMMISSION_BASE_KEY,
  PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
  REFERRAL_CREDIT_WINDOW_DAYS_KEY,
  REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
} from '../settings/agent-program-settings';
import { FakeAgentCommissionPolicy } from '../testing/fake-agent-commission-policy';
import { FakeAgentSettings } from '../testing/fake-agent-platform';
import { AgentConfigError, AgentConfigService } from './agent-config.service';

const FULL_SETTINGS = {
  [REFERRAL_CREDIT_WINDOW_DAYS_KEY]: 60,
  [PAYOUT_MINIMUM_AMOUNT_PAISE_KEY]: 50_000,
  [REFERRAL_MEMBER_DISCOUNT_BPS_KEY]: 500,
};

const make = (
  settings: Record<string, unknown> = FULL_SETTINGS,
  holdDays: number | null = 14,
) => {
  const store = new FakeAgentSettings(settings);
  const policy = new FakeAgentCommissionPolicy(holdDays);
  const service = new AgentConfigService(
    store,
    new StaticAgentContent(),
    policy,
  );
  return { store, policy, service };
};

describe('AgentConfigService.getConfig', () => {
  describe('settings', () => {
    it('returns the values from the settings and the commission policy', async () => {
      const { service } = make();
      const config = await service.getConfig();
      expect(config.settings).toEqual({
        holdDays: 14,
        creditWindowDays: 60,
        minPayoutPaise: 50_000,
        referredMemberDiscountPercent: 5,
      });
    });

    it('reads settings on every call (a change needs no deploy)', async () => {
      const { service, store, policy } = make();
      await service.getConfig();
      store.set(REFERRAL_MEMBER_DISCOUNT_BPS_KEY, 1_000);
      store.set(REFERRAL_CREDIT_WINDOW_DAYS_KEY, 90);
      policy.set(7);
      const config = await service.getConfig();
      expect(config.settings).toMatchObject({
        holdDays: 7,
        creditWindowDays: 90,
        referredMemberDiscountPercent: 10,
      });
      expect(config.shareMessages[0].text.en).toContain('10% off');
    });

    it('turns basis points into an exact percent, including a fraction', async () => {
      const { service } = make({
        ...FULL_SETTINGS,
        [REFERRAL_MEMBER_DISCOUNT_BPS_KEY]: 550,
      });
      const config = await service.getConfig();
      expect(config.settings.referredMemberDiscountPercent).toBe(5.5);
      expect(config.shareMessages[0].text.en).toContain('get 5.5% off');
    });

    it('accepts 0 as a real value for every number', async () => {
      const { service } = make(
        {
          [REFERRAL_CREDIT_WINDOW_DAYS_KEY]: 0,
          [PAYOUT_MINIMUM_AMOUNT_PAISE_KEY]: 0,
          [REFERRAL_MEMBER_DISCOUNT_BPS_KEY]: 0,
        },
        0,
      );
      expect((await service.getConfig()).settings).toEqual({
        holdDays: 0,
        creditWindowDays: 0,
        minPayoutPaise: 0,
        referredMemberDiscountPercent: 0,
      });
    });
  });

  describe('missing settings fail clearly', () => {
    it.each([
      REFERRAL_CREDIT_WINDOW_DAYS_KEY,
      PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
      REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
    ])('names %s when it is not set', async (key) => {
      const { service, store } = make();
      store.remove(key);
      await expect(service.getConfig()).rejects.toThrow(AgentConfigError);
      await expect(service.getConfig()).rejects.toThrow(key);
    });

    it('treats null as missing, never as a default', async () => {
      const { service } = make({
        ...FULL_SETTINGS,
        [PAYOUT_MINIMUM_AMOUNT_PAISE_KEY]: null,
      });
      await expect(service.getConfig()).rejects.toThrow(
        PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
      );
    });

    it('lists every missing value together, including the hold days', async () => {
      const { service } = make({}, null);
      const error = await service.getConfig().catch((e: unknown) => e);
      expect(error).toBeInstanceOf(AgentConfigError);
      expect((error as AgentConfigError).missing).toEqual([
        REFERRAL_CREDIT_WINDOW_DAYS_KEY,
        PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
        REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
        'hold days of the active commission policy',
      ]);
    });

    it('fails when only the hold days are missing', async () => {
      const { service } = make(FULL_SETTINGS, null);
      await expect(service.getConfig()).rejects.toThrow(
        /missing hold days of the active commission policy/,
      );
    });
  });

  describe('invalid settings fail clearly', () => {
    it.each([
      [REFERRAL_MEMBER_DISCOUNT_BPS_KEY, 'five'],
      [REFERRAL_MEMBER_DISCOUNT_BPS_KEY, 10_001],
      [REFERRAL_CREDIT_WINDOW_DAYS_KEY, -1],
      [PAYOUT_MINIMUM_AMOUNT_PAISE_KEY, 500.5],
    ])(
      'is unavailable (not a 500) and names %s as invalid when it is %p, never the value',
      async (key, value) => {
        const { service } = make({ ...FULL_SETTINGS, [key]: value });
        const error = await service.getConfig().catch((e: unknown) => e);
        expect(error).toBeInstanceOf(AgentConfigError);
        expect((error as AgentConfigError).missing).toEqual([]);
        expect((error as AgentConfigError).invalid).toEqual([key]);
        expect((error as Error).message).toBe(
          `Agent config is not available: invalid ${key}.`,
        );
        expect((error as Error).message).not.toContain(String(value));
      },
    );

    it.each([-1, 1.5])(
      'names the hold days as invalid when they are %p',
      async (holdDays) => {
        const { service } = make(FULL_SETTINGS, holdDays);
        const error = await service.getConfig().catch((e: unknown) => e);
        expect(error).toBeInstanceOf(AgentConfigError);
        expect((error as AgentConfigError).invalid).toEqual([
          'hold days of the active commission policy',
        ]);
      },
    );

    it('lists missing and invalid together', async () => {
      const { service } = make(
        {
          [REFERRAL_MEMBER_DISCOUNT_BPS_KEY]: 'five',
          [PAYOUT_MINIMUM_AMOUNT_PAISE_KEY]: null,
        },
        null,
      );
      const error = await service.getConfig().catch((e: unknown) => e);
      expect((error as Error).message).toBe(
        'Agent config is not available: missing referral.credit_window_days, payout.minimum_amount_paise, hold days of the active commission policy; invalid referral.member_discount_bps.',
      );
    });

    it('is not broken by an unrelated invalid setting', async () => {
      const { service } = make({
        ...FULL_SETTINGS,
        [COMMISSION_BASE_KEY]: 'JUNK',
        [AGENT_CLIENT_DRAFT_LIMIT_KEY]: -5,
      });
      await expect(service.getConfig()).resolves.toBeDefined();
    });
  });

  describe('labels', () => {
    it('returns every label group from the content file', async () => {
      const { service } = make();
      const config = await service.getConfig();
      expect(config.statusLabels).toEqual(AGENT_CONTENT.statusLabels);
      expect(config.stageLabels).toEqual(AGENT_CONTENT.stageLabels);
      expect(config.commissionStatusLabels).toEqual(
        AGENT_CONTENT.commissionStatusLabels,
      );
      expect(config.payoutStatusLabels).toEqual(
        AGENT_CONTENT.payoutStatusLabels,
      );
    });

    it('English labels are English and other Tamil labels stay "to be supplied"', async () => {
      const config = await make().service.getConfig();
      expect(config.statusLabels.SUSPENDED).toEqual({
        en: 'Paused',
        ta: '<to be supplied>',
      });
      expect(config.payoutStatusLabels.CREATED).toEqual({
        en: 'Processing',
        ta: '<to be supplied>',
      });
    });

    it('does not hand out the shared content (editing a result changes nothing)', async () => {
      const { service } = make();
      const first = await service.getConfig();
      first.statusLabels.ACTIVE.en = 'changed';
      first.shareMessages[0].text.en = 'changed';
      const second = await service.getConfig();
      expect(second.statusLabels.ACTIVE.en).toBe('Active');
      expect(second.shareMessages[0].text.en).toContain('Join Nenjam');
    });
  });

  describe('share messages', () => {
    it('English: {discount_percent} is filled in, the other placeholders stay', async () => {
      const [message] = (await make().service.getConfig()).shareMessages;
      expect(message.id).toBe('default');
      expect(message.text.en).toBe(
        "Hi! I'm {agent_name}. Join Nenjam, a trusted matrimony app, and use my referral code {code} when you sign up to get 5% off your first plan.\n{link}",
      );
    });

    it('Tamil: the approved wording, {discount_percent} filled in', async () => {
      const [message] = (await make().service.getConfig()).shareMessages;
      expect(message.text.ta).toBe(
        'வணக்கம்! நான் {agent_name}. நம்பகமான திருமண வரன் தேடல் செயலியான "நெஞ்சம்" (Nenjam)-இல் இணையுங்கள். பதிவு செய்யும்போது என் பரிந்துரைக் குறியீடு {code} பயன்படுத்தினால், உங்கள் முதல் திட்டத்தில் 5% தள்ளுபடி கிடைக்கும்.\n{link}',
      );
    });

    it('leaves no {discount_percent} behind in either language', async () => {
      const [message] = (await make().service.getConfig()).shareMessages;
      expect(message.text.en).not.toContain('{discount_percent}');
      expect(message.text.ta).not.toContain('{discount_percent}');
    });

    it('English renders fully per agent and code, with the link on its own last line', async () => {
      const [message] = (await make().service.getConfig()).shareMessages;
      const rendered = renderShareMessage(message.text.en, {
        agentName: 'Ravi Kumar',
        code: 'NM7K2P9X',
        discountPercent: 5,
        link: 'https://example.invalid/r/NM7K2P9X',
      });
      expect(rendered).toBe(
        "Hi! I'm Ravi Kumar. Join Nenjam, a trusted matrimony app, and use my referral code NM7K2P9X when you sign up to get 5% off your first plan.\nhttps://example.invalid/r/NM7K2P9X",
      );
    });

    it('never shows "K.." for an agent whose name ends in a full stop (English and Tamil)', async () => {
      const [message] = (await make().service.getConfig()).shareMessages;
      const english = renderShareMessage(message.text.en, {
        agentName: 'Ravi K.',
        code: 'NM7K2P9X',
        discountPercent: 5,
        link: null,
      });
      expect(english).toContain("I'm Ravi K. Join Nenjam");
      expect(english).not.toContain('..');
      const tamil = renderShareMessage(message.text.ta, {
        agentName: 'ரவி கு.',
        code: 'NM7K2P9X',
        discountPercent: 5,
        link: null,
      });
      expect(tamil).toContain('நான் ரவி கு. நம்பகமான');
      expect(tamil).not.toContain('..');
    });

    it('drops the link line (and leaves no blank line) when there is no link', async () => {
      const [message] = (await make().service.getConfig()).shareMessages;
      for (const link of [null, '', '   ']) {
        for (const text of [message.text.en, message.text.ta]) {
          const rendered = renderShareMessage(text, {
            agentName: 'Ravi Kumar',
            code: 'NM7K2P9X',
            discountPercent: 5,
            link,
          });
          expect(rendered).not.toContain('{link}');
          expect(rendered).not.toContain('\n');
          expect(rendered).toContain('NM7K2P9X');
          expect(rendered.endsWith('\n')).toBe(false);
        }
      }
    });

    it('an agent named like a placeholder is not expanded a second time', async () => {
      const [message] = (await make().service.getConfig()).shareMessages;
      const rendered = renderShareMessage(message.text.en, {
        agentName: '{code}',
        code: 'NM7K2P9X',
        discountPercent: 5,
        link: null,
      });
      expect(rendered).toContain("I'm {code}.");
    });
  });
});
