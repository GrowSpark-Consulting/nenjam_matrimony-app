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

/** Thrown when a required setting or policy value has not been set. */
export class AgentConfigError extends Error {
  constructor(public readonly missing: string[]) {
    super(`Agent config is not available: missing ${missing.join(', ')}.`);
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
   * Throws `AgentConfigError` listing every missing value, or a RangeError
   * naming the setting when one is present but invalid. Never supplies a
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
    const parsed = parseAgentProgramSettings(raw);
    const missing: string[] = REQUIRED_SETTING_KEYS.filter((key) =>
      parsed.missing.includes(key),
    );
    if (holdDays === null) missing.push(HOLD_DAYS_SOURCE);
    if (holdDays === null || missing.length > 0) {
      throw new AgentConfigError(missing);
    }

    if (!Number.isSafeInteger(holdDays) || holdDays < 0) {
      throw new RangeError(`The ${HOLD_DAYS_SOURCE} must be an integer >= 0.`);
    }

    const { settings } = parsed;
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
