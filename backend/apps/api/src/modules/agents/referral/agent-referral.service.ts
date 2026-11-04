/**
 * An agent's referral codes, links and referred members:
 * GET /agent/referral-links, GET /agent/referrals, GET /agent/referrals/{id}.
 *
 * Not wired into any module or controller yet. Every method starts with
 * `AgentMeService.assertCan`, and every read is scoped to the CALLER's own
 * agent id: an agent can never see another agent's referral, and asking for
 * one is indistinguishable from asking for one that does not exist.
 *
 * Agents only ever see the allow-listed `AgentReferralView`; rejected
 * attributions (kept for review) are never shown.
 */
import type { AgentMeService } from '../agent/agent-me.service';
import { agentCapabilitiesFor } from '../agent/agent-status';
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import { AgentConfigError } from '../config/agent-config.service';
import { AgentServiceError } from '../errors/agent-service-error';
import type {
  AgentContentPort,
  AgentLocalizedText,
} from '../ports/agent-content.port';
import type {
  AgentMemberReadPort,
  AttributionPageCursor,
  ReferralAttributionRecord,
  ReferralAttributionRepository,
  ReferralCodeRepository,
} from '../ports/agent-data-ports';
import type { CommissionRepository } from '../ports/agent-commission-ports';
import type { AgentSettingsPort } from '../ports/agent-platform-ports';
import {
  AgentReferralView,
  ReferralStage,
  toAgentReferralView,
} from './agent-referral-view';
import { renderShareMessage } from './render-share-message';
import {
  parseAgentProgramSettings,
  REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
} from '../settings/agent-program-settings';

/** The page size rules of the API contract (`Limit` parameter). */
export const DEFAULT_REFERRALS_PAGE_LIMIT = 20;
export const MAX_REFERRALS_PAGE_LIMIT = 50;

const STAGES: readonly ReferralStage[] = [
  'REGISTERED',
  'PROFILE_COMPLETE',
  'PURCHASED',
];

export interface AgentReferralShareMessage {
  id: string;
  text: AgentLocalizedText;
}

export interface AgentReferralLink {
  codeId: string;
  code: string;
  isPrimary: boolean;
  /** Null until the public web address is decided. */
  link: string | null;
  /** The string to encode into a QR code (the same as `link`). */
  qrPayload: string | null;
  shareMessages: AgentReferralShareMessage[];
  /** False while the agent is paused. */
  shareable: boolean;
}

export interface AgentReferralsQuery {
  cursor?: string;
  limit?: number;
  stage?: string;
}

export interface AgentReferralsPage {
  items: AgentReferralView[];
  /** Opaque; null on the last page. */
  nextCursor: string | null;
}

export interface AgentReferralServiceDeps {
  access: Pick<AgentMeService, 'assertCan'>;
  codes: ReferralCodeRepository;
  attributions: ReferralAttributionRepository;
  members: AgentMemberReadPort;
  /** The commission of a referral (at most one), for its public status. */
  commissions: Pick<CommissionRepository, 'findByAttributionId'>;
  content: AgentContentPort;
  settings: AgentSettingsPort;
  /** The public link for a code; null while the web address is not decided. */
  linkFor?: (code: string) => string | null;
}

export class AgentReferralService {
  constructor(private readonly deps: AgentReferralServiceDeps) {}

  /** GET /agent/referral-links. Not paginated: an agent holds a handful. */
  async getLinks(
    claims: AgentAccessClaims,
  ): Promise<{ items: AgentReferralLink[] }> {
    const agent = await this.deps.access.assertCan(claims, 'viewReferralLinks');
    const shareable = agentCapabilitiesFor(agent.status).shareReferralLinks;
    const [codes, content, discountPercent] = await Promise.all([
      this.deps.codes.listByAgent(agent.id),
      this.deps.content.getContent(),
      this.discountPercent(),
    ]);

    const items = codes
      .filter((code) => code.isActive)
      .sort(
        (a, b) =>
          Number(b.isPrimary) - Number(a.isPrimary) ||
          a.createdAt.getTime() - b.createdAt.getTime(),
      )
      .map((code): AgentReferralLink => {
        const link = this.deps.linkFor?.(code.code) ?? null;
        const render = (template: string) =>
          renderShareMessage(template, {
            agentName: agent.name,
            code: code.code,
            discountPercent,
            link,
          });
        return {
          codeId: code.id,
          code: code.code,
          isPrimary: code.isPrimary,
          link,
          qrPayload: link,
          shareMessages: content.shareMessageTemplates.map((template) => ({
            id: template.id,
            text: {
              en: render(template.text.en),
              ta: render(template.text.ta),
            },
          })),
          shareable,
        };
      });
    return { items };
  }

  /** GET /agent/referrals: newest first, cursor paginated. */
  async listReferrals(
    claims: AgentAccessClaims,
    query: AgentReferralsQuery = {},
  ): Promise<AgentReferralsPage> {
    const agent = await this.deps.access.assertCan(claims, 'viewReferrals');
    const { limit, stage, after } = parseQuery(query);

    const pageSize = limit + 1;
    const matched: Array<{
      record: ReferralAttributionRecord;
      view: AgentReferralView;
    }> = [];
    let position = after;
    while (matched.length < pageSize) {
      const batch = await this.deps.attributions.listPageByAgent(agent.id, {
        limit: pageSize,
        after: position,
      });
      if (batch.length === 0) break;
      for (const record of batch) {
        const view = await this.viewOf(record);
        if (view !== null && (stage === undefined || view.stage === stage)) {
          matched.push({ record, view });
          if (matched.length === pageSize) break;
        }
      }
      const last = batch[batch.length - 1];
      position = { at: last.attributedAt, id: last.id };
      if (batch.length < pageSize) break;
    }

    const items = matched.slice(0, limit);
    const hasMore = matched.length > limit;
    return {
      items: items.map((entry) => entry.view),
      nextCursor: hasMore ? encodeCursor(items[items.length - 1].record) : null,
    };
  }

  /** GET /agent/referrals/{id}. Another agent's referral looks like a missing one. */
  async getReferral(
    claims: AgentAccessClaims,
    id: string,
  ): Promise<AgentReferralView> {
    const agent = await this.deps.access.assertCan(claims, 'viewReferrals');
    const record =
      typeof id === 'string' && id.length > 0
        ? await this.deps.attributions.findByIdForAgent(id, agent.id)
        : null;
    const view = record === null ? null : await this.viewOf(record);
    if (view === null) throw new AgentServiceError('REFERRAL_NOT_FOUND');
    return view;
  }

  /** The allow-listed view, or null for a hidden or vanished referral. */
  private async viewOf(
    record: ReferralAttributionRecord,
  ): Promise<AgentReferralView | null> {
    if (record.status === 'REJECTED') return null;
    // A deleted member has nothing left to show.
    if (record.memberId === null) return null;
    const fields = await this.deps.members.getReferralViewFields(
      record.memberId,
    );
    if (fields === null) return null;
    // The public status only (toAgentReferralView maps it): review states
    // show as ON_HOLD, REVERSED as CANCELLED; no commission yet is null.
    const commission = await this.deps.commissions.findByAttributionId(
      record.id,
    );
    return toAgentReferralView({
      ...fields,
      attributionId: record.id,
      commissionStatus: commission?.status ?? null,
    });
  }

  private async discountPercent(): Promise<number> {
    const parsed = parseAgentProgramSettings(
      await this.deps.settings.getMany([REFERRAL_MEMBER_DISCOUNT_BPS_KEY]),
    );
    const bps = parsed.settings.referralMemberDiscountBps;
    if (bps === undefined) {
      throw new AgentConfigError([REFERRAL_MEMBER_DISCOUNT_BPS_KEY]);
    }
    return bps / 100;
  }
}

function parseQuery(query: AgentReferralsQuery): {
  limit: number;
  stage: ReferralStage | undefined;
  after: AttributionPageCursor | undefined;
} {
  const invalid: string[] = [];

  let limit = DEFAULT_REFERRALS_PAGE_LIMIT;
  if (query.limit !== undefined) {
    if (
      !Number.isSafeInteger(query.limit) ||
      query.limit < 1 ||
      query.limit > MAX_REFERRALS_PAGE_LIMIT
    ) {
      invalid.push('limit');
    } else {
      limit = query.limit;
    }
  }

  let stage: ReferralStage | undefined;
  if (query.stage !== undefined) {
    if (STAGES.includes(query.stage as ReferralStage)) {
      stage = query.stage as ReferralStage;
    } else {
      invalid.push('stage');
    }
  }

  let after: AttributionPageCursor | undefined;
  if (query.cursor !== undefined) {
    after = decodeCursor(query.cursor);
    if (after === undefined) invalid.push('cursor');
  }

  if (invalid.length > 0) {
    throw new AgentServiceError('VALIDATION_FAILED', { fields: invalid });
  }
  return { limit, stage, after };
}

/** Opaque to clients: base64url of { t: ISO time, i: attribution id }. */
function encodeCursor(record: ReferralAttributionRecord): string {
  return Buffer.from(
    JSON.stringify({ t: record.attributedAt.toISOString(), i: record.id }),
  ).toString('base64url');
}

function decodeCursor(cursor: string): AttributionPageCursor | undefined {
  if (
    typeof cursor !== 'string' ||
    cursor.length === 0 ||
    cursor.length > 200
  ) {
    return undefined;
  }
  try {
    const parsed = JSON.parse(
      Buffer.from(cursor, 'base64url').toString('utf8'),
    ) as { t?: unknown; i?: unknown };
    if (typeof parsed.t !== 'string' || typeof parsed.i !== 'string') {
      return undefined;
    }
    const at = new Date(parsed.t);
    if (
      Number.isNaN(at.getTime()) ||
      at.toISOString() !== parsed.t ||
      parsed.i.length === 0 ||
      parsed.i.length > 100
    ) {
      return undefined;
    }
    return { at, id: parsed.i };
  } catch {
    return undefined;
  }
}
