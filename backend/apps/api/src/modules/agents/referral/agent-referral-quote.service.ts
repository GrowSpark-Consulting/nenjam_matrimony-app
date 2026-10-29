/**
 * `quoteReferral`: what a referral discount would be for a member about to pay,
 * for the checkout. Not wired into any module.
 *
 * READ-ONLY. It never creates or changes an attribution, a code, an agent, an
 * audit row or a payment. The attach happens later, when the payment succeeds,
 * with `heldReferralCodeId`. The one thing it records is the attempt counter
 * (rate limiting), and only when a promo code was typed.
 *
 * AN INVALID CODE NEVER BLOCKS PAYMENT. Every problem with a typed code, a
 * rate limit included, comes back as a quote with no discount and a
 * `rejectedReason`. The only errors thrown are `UNAUTHORIZED` (unknown member),
 * a `RangeError` for a malformed amount, and `AgentConfigError` when a setting
 * the answer needs is missing (the checkout should treat that as "no
 * discount", see the report).
 *
 * Rules, in order:
 *  1. The discount is for the member's FIRST paid plan only (`NOT_FIRST_PLAN`).
 *  2. A member already credited to an agent uses THAT agent; the first agent
 *     always stays. A typed code is then ignored (`ALREADY_ATTRIBUTED` is
 *     reported alongside the discount, if there is one). The discount needs the
 *     attribution to be ACTIVE and, when `referral.discount_only_in_credit_window`
 *     is true, to be inside its window.
 *  3. Otherwise a typed code is normalised and judged by `decideAttribution`
 *     as if it were entered at payment: it must exist, be active, belong to an
 *     ACTIVE agent, not be the member's own phone and not conflict with another
 *     account on the same phone. A paused agent (`SUSPENDED`) gives no discount
 *     (`AGENT_PAUSED`).
 *  4. The amount comes from `computeReferralDiscount` and the settings.
 *
 * Rejection reasons: INVALID (unknown, malformed, inactive, a terminated or
 * not-yet-approved agent, a rate-limited attempt, a rejected attribution),
 * ALREADY_ATTRIBUTED, NOT_FIRST_PLAN, AGENT_PAUSED, SELF_REFERRAL,
 * PHONE_NOT_VERIFIED (the member has no verified phone: no credit is possible).
 */
import { AgentConfigError } from '../config/agent-config.service';
import { AgentServiceError } from '../errors/agent-service-error';
import type {
  AgentMemberReadPort,
  AgentRepository,
  ReferralAttributionRecord,
  ReferralAttributionRepository,
  ReferralCodeAttemptStore,
  ReferralCodeRepository,
} from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type { AgentSettingsPort } from '../ports/agent-platform-ports';
import {
  parseAgentProgramSettings,
  REFERRAL_CREDIT_WINDOW_DAYS_KEY,
  REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY,
  REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
} from '../settings/agent-program-settings';
import { splitName } from './agent-referral-code.service';
import { toDisplayName } from './agent-referral-view';
import {
  computeReferralDiscount,
  ReferralDiscount,
} from './compute-referral-discount';
import { decideAttribution } from './decide-attribution';
import { normalizeReferralCode } from './normalize-referral-code';
import { ReferralAttemptLimiter } from './referral-attempt-limiter';

export type ReferralQuoteRejectedReason =
  | 'INVALID'
  | 'ALREADY_ATTRIBUTED'
  | 'NOT_FIRST_PLAN'
  | 'AGENT_PAUSED'
  | 'SELF_REFERRAL'
  | 'PHONE_NOT_VERIFIED';

export interface ReferralQuoteInput {
  memberId: string;
  /** What the member typed at checkout; absent or blank means none. */
  promoCode?: string | null;
  /** The plan price being bought. Validated only; it does not change the maths. */
  planPriceId: string;
  /** The list price in paise, before any discount. */
  listAmountPaise: number;
}

export interface ReferralQuote {
  /** The rate applied (basis points); 0 when there is no discount. */
  discountBps: number;
  discountPaise: number;
  discountSource: ReferralDiscount['source'];
  /**
   * The list price minus the discount: the TAXABLE amount. Plan prices are
   * exclusive of GST, so GST is added on top of this (the payments code
   * computes and stores it); this is not what the member pays.
   */
  taxableAfterDiscountPaise: number;
  /** The typed code to hold on the payment so it can be attached when paid. */
  heldReferralCodeId?: string;
  /** "Ravi K." - the agent the discount comes from. */
  agentDisplayName?: string;
  rejectedReason?: ReferralQuoteRejectedReason;
}

export interface AgentReferralQuoteServiceDeps {
  settings: AgentSettingsPort;
  attempts: ReferralCodeAttemptStore;
  codes: ReferralCodeRepository;
  agents: AgentRepository;
  attributions: ReferralAttributionRepository;
  members: AgentMemberReadPort;
  clock: AgentClock;
}

interface Resolved {
  agentName: string;
  /** Whether the agent may give a discount at all. */
  eligible: boolean;
  withinCreditWindow: boolean;
  heldReferralCodeId?: string;
  rejectedReason?: ReferralQuoteRejectedReason;
}

export class AgentReferralQuoteService {
  private readonly limiter: ReferralAttemptLimiter;

  constructor(private readonly deps: AgentReferralQuoteServiceDeps) {
    this.limiter = new ReferralAttemptLimiter(deps);
  }

  async quote(input: ReferralQuoteInput): Promise<ReferralQuote> {
    if (typeof input.memberId !== 'string' || input.memberId.length === 0) {
      throw new RangeError('memberId must be a non-empty string.');
    }
    if (typeof input.planPriceId !== 'string' || input.planPriceId === '') {
      throw new RangeError('planPriceId must be a non-empty string.');
    }
    // Validates the amount (a non-negative integer) before anything is read.
    const list = computeReferralDiscount({
      listAmountPaise: input.listAmountPaise,
      referralDiscountBps: 0,
      referralEligible: false,
      withinCreditWindow: false,
      onlyInCreditWindow: false,
    });

    const member = await this.deps.members.getMember(input.memberId);
    if (member === null) throw new AgentServiceError('UNAUTHORIZED');

    // 1. First paid plan only. Nothing else is looked at, nothing is counted.
    if (member.hasPaid) return none(list, 'NOT_FIRST_PLAN');

    const typed =
      typeof input.promoCode === 'string' && input.promoCode.trim() !== '';

    const existing = await this.deps.attributions.findByMemberId(
      input.memberId,
    );
    const resolved =
      existing !== null
        ? await this.fromExistingAttribution(existing, typed)
        : typed
          ? await this.fromTypedCode(input.memberId, member, input.promoCode)
          : null;
    if (resolved === null) return none(list);
    if (!resolved.eligible) return none(list, resolved.rejectedReason);

    // The settings are only needed once a discount is possible.
    const { bps, onlyInCreditWindow } = await this.discountSettings();
    const discount = computeReferralDiscount({
      listAmountPaise: input.listAmountPaise,
      referralDiscountBps: bps,
      referralEligible: true,
      withinCreditWindow: resolved.withinCreditWindow,
      onlyInCreditWindow,
    });
    const name = splitName(resolved.agentName);
    const quote: ReferralQuote = {
      discountBps: discount.discountPaise > 0 ? bps : 0,
      discountPaise: discount.discountPaise,
      discountSource: discount.source,
      taxableAfterDiscountPaise: discount.taxableAfterDiscountPaise,
    };
    if (discount.discountPaise > 0) {
      quote.agentDisplayName = toDisplayName(name.first ?? '', name.last);
      if (resolved.heldReferralCodeId !== undefined) {
        quote.heldReferralCodeId = resolved.heldReferralCodeId;
      }
    }
    if (resolved.rejectedReason !== undefined) {
      quote.rejectedReason = resolved.rejectedReason;
    }
    return quote;
  }

  /** The first agent always stays; a typed code does not replace them. */
  private async fromExistingAttribution(
    attribution: ReferralAttributionRecord,
    typed: boolean,
  ): Promise<Resolved> {
    const conflict = typed ? 'ALREADY_ATTRIBUTED' : undefined;
    const refused = (
      rejectedReason: ReferralQuoteRejectedReason | undefined,
    ): Resolved => ({
      agentName: '',
      eligible: false,
      withinCreditWindow: false,
      rejectedReason: rejectedReason ?? conflict,
    });

    switch (attribution.status) {
      case 'CONVERTED':
        return refused('NOT_FIRST_PLAN');
      case 'REJECTED':
        return refused('INVALID');
      case 'EXPIRED':
        return refused(undefined);
      case 'ACTIVE':
        break;
    }
    const agent = await this.deps.agents.findById(attribution.agentId);
    if (agent === null) return refused('INVALID');
    if (agent.status === 'SUSPENDED') return refused('AGENT_PAUSED');
    if (agent.status !== 'ACTIVE') return refused('INVALID');
    return {
      agentName: agent.name,
      eligible: true,
      withinCreditWindow:
        this.deps.clock.now().getTime() <= attribution.windowEndsAt.getTime(),
      rejectedReason: conflict,
    };
  }

  /** A typed code for a member with no attribution yet. */
  private async fromTypedCode(
    memberId: string,
    member: { phoneHash: string | null },
    rawCode: unknown,
  ): Promise<Resolved> {
    const refused = (
      rejectedReason: ReferralQuoteRejectedReason,
    ): Resolved => ({
      agentName: '',
      eligible: false,
      withinCreditWindow: false,
      rejectedReason,
    });

    const code = normalizeReferralCode(rawCode);
    try {
      await this.limiter.check(`quote:${memberId}`, code);
    } catch (error) {
      // Never block a payment: a limited attempt is simply not used.
      if (error instanceof AgentServiceError && error.code === 'RATE_LIMITED') {
        return refused('INVALID');
      }
      throw error;
    }
    if (code === null) return refused('INVALID');

    const record = await this.deps.codes.findByCode(code);
    const agent =
      record === null ? null : await this.deps.agents.findById(record.agentId);
    const phoneCredited =
      member.phoneHash === null
        ? false
        : await this.deps.attributions.isPhoneHashCredited(member.phoneHash);

    const decision = decideAttribution({
      // Quoted at payment: the code would be attached as it is paid for.
      source: 'ENTERED_AT_PAYMENT',
      codeFound: record !== null && agent !== null,
      codeActive: record?.isActive ?? false,
      agentStatus: agent?.status ?? '',
      memberPhoneHash: member.phoneHash,
      agentPhoneHash: agent?.phoneHash ?? null,
      memberAlreadyAttributed: false,
      phoneAlreadyCredited: phoneCredited,
      memberHasPaid: false,
      now: this.deps.clock.now(),
      creditWindowDays: await this.creditWindowDays(),
    });
    if (!decision.ok) {
      switch (decision.reason) {
        case 'AGENT_NOT_ACTIVE':
          return refused(
            agent?.status === 'SUSPENDED' ? 'AGENT_PAUSED' : 'INVALID',
          );
        case 'SELF_REFERRAL':
          return refused('SELF_REFERRAL');
        case 'ALREADY_ATTRIBUTED':
        case 'PHONE_ALREADY_CREDITED':
          return refused('ALREADY_ATTRIBUTED');
        case 'ALREADY_PAID':
          return refused('NOT_FIRST_PLAN');
        case 'PHONE_NOT_VERIFIED':
          return refused('PHONE_NOT_VERIFIED');
        default:
          return refused('INVALID');
      }
    }
    // decideAttribution only succeeds when both exist.
    if (record === null || agent === null) return refused('INVALID');
    return {
      agentName: agent.name,
      eligible: true,
      // It is being credited as it is paid for, so the window is open.
      withinCreditWindow: true,
      heldReferralCodeId: record.id,
    };
  }

  private async discountSettings(): Promise<{
    bps: number;
    onlyInCreditWindow: boolean;
  }> {
    const keys = [
      REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
      REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY,
    ];
    const parsed = parseAgentProgramSettings(
      await this.deps.settings.getMany(keys),
    );
    const bps = parsed.settings.referralMemberDiscountBps;
    const only = parsed.settings.referralDiscountOnlyInCreditWindow;
    if (bps === undefined || only === undefined) {
      throw new AgentConfigError(
        keys.filter((k) => parsed.missing.includes(k)),
      );
    }
    return { bps, onlyInCreditWindow: only };
  }

  private async creditWindowDays(): Promise<number> {
    const parsed = parseAgentProgramSettings(
      await this.deps.settings.getMany([REFERRAL_CREDIT_WINDOW_DAYS_KEY]),
    );
    const days = parsed.settings.referralCreditWindowDays;
    if (days === undefined) {
      throw new AgentConfigError([REFERRAL_CREDIT_WINDOW_DAYS_KEY]);
    }
    return days;
  }
}

/** A quote with no discount, optionally with the reason a code was not used. */
function none(
  list: ReferralDiscount,
  rejectedReason?: ReferralQuoteRejectedReason,
): ReferralQuote {
  const quote: ReferralQuote = {
    discountBps: 0,
    discountPaise: 0,
    discountSource: 'NONE',
    taxableAfterDiscountPaise: list.taxableAfterDiscountPaise,
  };
  if (rejectedReason !== undefined) quote.rejectedReason = rejectedReason;
  return quote;
}
