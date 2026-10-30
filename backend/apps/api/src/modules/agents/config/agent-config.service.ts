/**
 * Logic behind GET /agent/config.
 *
 * Not wired into any module or controller yet. Settings are read through
 * `AgentSettingsPort` on every call (so a change needs no deploy and nothing
 * is cached or defaulted here); labels and share-message templates come from
 * `AgentContentPort`; the hold period from `AgentCommissionPolicyPort`.
 */
import type { AgentCommissionPolicyPort } from '../ports/agent-commission-policy.port';
import type {
  AgentContentPort,
  AgentLocalizedText,
  AgentShareMessageTemplate,
} from '../ports/agent-content.port';
import type { AgentSettingsPort } from '../ports/agent-platform-ports';
import { renderShareMessage } from '../referral/render-share-message';
import {
  agentProgramSettingProblem,
  parseAgentProgramSettings,
  PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
  REFERRAL_CREDIT_WINDOW_DAYS_KEY,
  REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
} from '../settings/agent-program-settings';

/** What the config response needs from the settings, in this order. */
const REQUIRED_SETTING_KEYS = [
  REFERRAL_CREDIT_WINDOW_DAYS_KEY,
  PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
  REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
] as const;

const HOLD_DAYS_SOURCE = 'hold days of the active commission policy';

const BASIS_POINTS_PER_PERCENT = 100;

export interface AgentConfigSettings {
  holdDays: number;
  creditWindowDays: number;
  minPayoutPaise: number;
  /** Basis points / 100, so 500 bps is 5 and 550 bps is 5.5. */
  referredMemberDiscountPercent: number;
}

export interface AgentConfig {
  statusLabels: Record<string, AgentLocalizedText>;
  stageLabels: Record<string, AgentLocalizedText>;
  commissionStatusLabels: Record<string, AgentLocalizedText>;
  payoutStatusLabels: Record<string, AgentLocalizedText>;
  /**
   * Templates with `{discount_percent}` filled in. `{agent_name}`, `{code}`
   * and `{link}` stay as placeholders for the per-link rendering.
   */
  shareMessages: AgentShareMessageTemplate[];
  settings: AgentConfigSettings;
}

/**
 * Thrown when a required setting or policy value is not set (`missing`) or
 * is set to a value that cannot be used (`invalid`). Answered as 503
 * AGENT_PROGRAM_UNAVAILABLE; the message names keys only, never values.
 */
export class AgentConfigError extends Error {
  constructor(
    public readonly missing: string[],
    public readonly invalid: string[] = [],
  ) {
    const parts = [
      ...(missing.length > 0 ? [`missing ${missing.join(', ')}`] : []),
      ...(invalid.length > 0 ? [`invalid ${invalid.join(', ')}`] : []),
    ];
    super(`Agent config is not available: ${parts.join('; ')}.`);
    this.name = 'AgentConfigError';
  }
}

export class AgentConfigService {
  constructor(
    private readonly settings: AgentSettingsPort,
    private readonly content: AgentContentPort,
    private readonly commissionPolicy: AgentCommissionPolicyPort,
  ) {}

  /**
   * Throws `AgentConfigError` listing every value that is missing or
   * present but unusable (a 503 that names the keys). Never supplies a
   * default.
   */
  async getConfig(): Promise<AgentConfig> {
    const [raw, holdDays, content] = await Promise.all([
      this.settings.getMany(REQUIRED_SETTING_KEYS),
      this.commissionPolicy.getActiveHoldDays(),
      this.content.getContent(),
    ]);

    // Only the keys this response needs are read, so an unrelated setting
    // that is wrong cannot break the config.
    const missing: string[] = [];
    const invalid: string[] = [];
    for (const key of REQUIRED_SETTING_KEYS) {
      const value = raw[key];
      if (value === undefined || value === null) missing.push(key);
      else if (agentProgramSettingProblem(key, value) !== null)
        invalid.push(key);
    }
    if (holdDays === null) missing.push(HOLD_DAYS_SOURCE);
    else if (!Number.isSafeInteger(holdDays) || holdDays < 0) {
      invalid.push(HOLD_DAYS_SOURCE);
    }
    if (missing.length > 0 || invalid.length > 0 || holdDays === null) {
      throw new AgentConfigError(missing, invalid);
    }

    const { settings } = parseAgentProgramSettings(raw);
    const discountPercent =
      settings.referralMemberDiscountBps! / BASIS_POINTS_PER_PERCENT;

    return {
      statusLabels: content.statusLabels,
      stageLabels: content.stageLabels,
      commissionStatusLabels: content.commissionStatusLabels,
      payoutStatusLabels: content.payoutStatusLabels,
      shareMessages: content.shareMessageTemplates.map((template) => ({
        id: template.id,
        text: {
          en: fillDiscount(template.text.en, discountPercent),
          ta: fillDiscount(template.text.ta, discountPercent),
        },
      })),
      settings: {
        holdDays,
        creditWindowDays: settings.referralCreditWindowDays!,
        minPayoutPaise: settings.payoutMinimumAmountPaise!,
        referredMemberDiscountPercent: discountPercent,
      },
    };
  }
}

/**
 * Fills only `{discount_percent}`, through the shared renderer. The other
 * placeholders are passed back as themselves: the renderer replaces in a
 * single pass, so they are inserted as literal text and not expanded again.
 */
function fillDiscount(template: string, discountPercent: number): string {
  return renderShareMessage(template, {
    agentName: '{agent_name}',
    code: '{code}',
    discountPercent,
    link: '{link}',
  });
}
