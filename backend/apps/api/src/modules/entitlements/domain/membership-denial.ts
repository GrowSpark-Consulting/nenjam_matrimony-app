import { ForbiddenException } from '@nestjs/common';
import type { SubscriptionPlanName } from '../../../../../../libs/database/generated/client';
import {
  definitionOf,
  type FeatureKey,
  type QuotaPeriod,
} from '../catalog/feature-catalog';

/**
 * The 403 a membership check answers with. A plain ForbiddenException with a
 * structured body — no custom exception class (the codebase deliberately has
 * none). `message` is always a complete human sentence, so a client that only
 * shows `message` (every current app build) still tells the member what
 * happened; `code`/`feature`/`upgradeTo` let a newer client render a paywall.
 */
export type MembershipDenialCode =
  | 'MEMBERSHIP_FEATURE_UNAVAILABLE'
  | 'MEMBERSHIP_LIMIT_REACHED'
  | 'MEMBERSHIP_FAIR_USE_LIMIT';

export interface MembershipDenialBody {
  statusCode: 403;
  error: 'Forbidden';
  code: MembershipDenialCode;
  feature: FeatureKey;
  message: string;
  /** The member's current plan. */
  plan: SubscriptionPlanName | null;
  limit?: number;
  used?: number;
  /** ISO time the allowance resets, for periodic quotas. */
  resetsAt?: string | null;
  /** The cheapest active plan that would allow this, if any. */
  upgradeTo?: SubscriptionPlanName | null;
}

export interface DenialContext {
  feature: FeatureKey;
  planCode: SubscriptionPlanName | null;
  planName: string | null;
  upgradeTo: { code: SubscriptionPlanName; name: string } | null;
}

function upgradeSentence(upgrade: DenialContext['upgradeTo']): string {
  return upgrade ? ` Upgrade to ${upgrade.name} to get more.` : '';
}

function planPhrase(planName: string | null): string {
  return planName ? `your ${planName} plan` : 'your plan';
}

function periodPhrase(period: QuotaPeriod): string {
  switch (period) {
    case 'DAY':
      return 'today';
    case 'MONTH':
      return 'this month';
    case 'SUBSCRIPTION':
      return 'for this plan';
  }
}

export function featureUnavailable(context: DenialContext): ForbiddenException {
  const { label } = definitionOf(context.feature);
  const unlock = context.upgradeTo
    ? ` Upgrade to ${context.upgradeTo.name} to unlock it.`
    : '';
  const body: MembershipDenialBody = {
    statusCode: 403,
    error: 'Forbidden',
    code: 'MEMBERSHIP_FEATURE_UNAVAILABLE',
    feature: context.feature,
    message: `${label} isn't included in ${planPhrase(context.planName)}.${unlock}`,
    plan: context.planCode,
    upgradeTo: context.upgradeTo?.code ?? null,
  };
  return new ForbiddenException(body);
}

export function quotaReached(
  context: DenialContext & {
    period: QuotaPeriod;
    limit: number;
    used: number;
    resetsAt: Date | null;
    fairUse: boolean;
  },
): ForbiddenException {
  const def = definitionOf(context.feature);
  const noun = def.noun ?? def.label.toLowerCase();
  const when = periodPhrase(context.period);
  const message = context.fairUse
    ? `You've reached the fair-use limit for ${noun} ${when}. Please try again later.`
    : `You've used all ${context.limit} ${noun} included in ${planPhrase(context.planName)} ${when}.${upgradeSentence(context.upgradeTo)}`;
  const body: MembershipDenialBody = {
    statusCode: 403,
    error: 'Forbidden',
    code: context.fairUse
      ? 'MEMBERSHIP_FAIR_USE_LIMIT'
      : 'MEMBERSHIP_LIMIT_REACHED',
    feature: context.feature,
    message,
    plan: context.planCode,
    limit: context.limit,
    used: context.used,
    resetsAt: context.resetsAt?.toISOString() ?? null,
    upgradeTo: context.fairUse ? null : (context.upgradeTo?.code ?? null),
  };
  return new ForbiddenException(body);
}

export function capReached(
  context: DenialContext & { limit: number; used: number },
): ForbiddenException {
  const def = definitionOf(context.feature);
  const noun = def.noun ?? def.label.toLowerCase();
  const body: MembershipDenialBody = {
    statusCode: 403,
    error: 'Forbidden',
    code: 'MEMBERSHIP_LIMIT_REACHED',
    feature: context.feature,
    message: `${planPhrase(context.planName).replace(/^your/, 'Your')} allows up to ${context.limit} ${noun}.${upgradeSentence(context.upgradeTo)}`,
    plan: context.planCode,
    limit: context.limit,
    used: context.used,
    upgradeTo: context.upgradeTo?.code ?? null,
  };
  return new ForbiddenException(body);
}
