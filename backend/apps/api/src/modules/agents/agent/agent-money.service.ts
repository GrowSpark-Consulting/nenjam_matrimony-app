/**
 * The signed-in agent's own money and device routes
 * (docs/agent-program/agent-api.openapi.yaml): GET /agent/commissions,
 * GET /agent/balance, GET /agent/payouts and POST /agent/devices.
 *
 * Every method starts with `AgentMeService.assertCan` (the capability table
 * in agent-status.ts decides which statuses may call it) and every read is
 * scoped to the CALLER's own agent id.
 *
 * Agents see the public commission statuses only (`COMMISSION_STATUS_PUBLIC_MAP`:
 * review and fraud states are ON_HOLD, REVERSED is CANCELLED). Dates are
 * calendar dates in Indian time. Amounts are integers in paise.
 *
 * The balance:
 * - `availablePaise`: the agent's ledger balance (approved credits, minus
 *   reversals, minus what is already in a payout), never shown below 0.
 * - `onHoldPaise`: the commissions an agent sees as ON_HOLD (amount not yet
 *   known counts 0).
 * - `paidPaise`: the gross amount of PAID payouts.
 * - `minPayoutPaise`: the `payout.minimum_amount_paise` setting (503 while it
 *   is not set); `canRequestPayout` is informational.
 */
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import { AgentServiceError } from '../errors/agent-service-error';
import { AgentConfigError } from '../config/agent-config.service';
import type {
  AgentLedgerRepository,
  AgentPayoutRecord,
  AgentPayoutRepository,
  CommissionRecord,
  CommissionRepository,
  CommissionStatusValue,
} from '../ports/agent-commission-ports';
import type {
  AgentCommissionDisplayPort,
  AgentDevicePlatform,
  AgentDeviceRepository,
} from '../ports/agent-money-read.port';
import type { AgentSettingsPort } from '../ports/agent-platform-ports';
import {
  COMMISSION_STATUS_PUBLIC_MAP,
  type PublicCommissionStatus,
} from '../referral/agent-referral-view';
import {
  parseAgentProgramSettings,
  PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
} from '../settings/agent-program-settings';
import type { AgentMeService } from './agent-me.service';
import { toIstDate } from './ist-date';

/** The page size rules of the API contract (`Limit` parameter). */
export const DEFAULT_MONEY_PAGE_LIMIT = 20;
export const MAX_MONEY_PAGE_LIMIT = 50;

/** How many rows one read takes while totalling the balance. */
const BALANCE_SCAN_BATCH = 200;

/**
 * Shown when a commission's member or plan can no longer be read (the member
 * deleted their account). Not personal data.
 */
export const UNKNOWN_REFERRAL_DISPLAY_NAME = 'Member';
export const UNKNOWN_PLAN_NAME = '';

const PUBLIC_STATUSES: readonly PublicCommissionStatus[] = [
  'ON_HOLD',
  'APPROVED',
  'PAID',
  'CANCELLED',
];
const DEVICE_PLATFORMS: readonly AgentDevicePlatform[] = ['ANDROID', 'IOS'];
const FCM_TOKEN_MIN = 20;
const FCM_TOKEN_MAX = 4096;

export interface AgentCommissionView {
  id: string;
  referralId: string;
  referralDisplayName: string;
  planName: string;
  basePaise: number;
  amountPaise: number;
  rate: { calcType: 'PERCENTAGE'; value: number };
  status: PublicCommissionStatus;
  earnedOn: string;
  holdEndsOn: string | null;
  approvedOn: string | null;
  paidOn: string | null;
}

export interface AgentPayoutView {
  id: string;
  amountPaise: number;
  status: AgentPayoutRecord['status'];
  reference: string | null;
  createdOn: string;
  paidOn: string | null;
  commissionCount: number;
}

export interface AgentBalance {
  onHoldPaise: number;
  availablePaise: number;
  paidPaise: number;
  minPayoutPaise: number;
  canRequestPayout: boolean;
}

export interface AgentPage<T> {
  items: T[];
  /** Opaque; null on the last page. */
  nextCursor: string | null;
}

export interface AgentMoneyQuery {
  cursor?: string;
  limit?: number;
  status?: string;
}

export interface AgentMoneyServiceDeps {
  access: Pick<AgentMeService, 'assertCan'>;
  commissions: CommissionRepository;
  ledger: AgentLedgerRepository;
  payouts: AgentPayoutRepository;
  display: AgentCommissionDisplayPort;
  devices: AgentDeviceRepository;
  settings: AgentSettingsPort;
}

interface PageCursor {
  at: Date;
  id: string;
}

export class AgentMoneyService {
  constructor(private readonly deps: AgentMoneyServiceDeps) {}

  /** GET /agent/commissions: newest first, cursor paginated. */
  async listCommissions(
    claims: AgentAccessClaims,
    query: AgentMoneyQuery = {},
  ): Promise<AgentPage<AgentCommissionView>> {
    const agent = await this.deps.access.assertCan(claims, 'viewCommissions');
    const { limit, after } = parsePage(query);
    const status = parsePublicStatus(query.status);

    const pageSize = limit + 1;
    const matched: CommissionRecord[] = [];
    let position = after;
    while (matched.length < pageSize) {
      const batch = await this.deps.commissions.listPage(
        { agentId: agent.id },
        { limit: pageSize, after: position },
      );
      if (batch.length === 0) break;
      for (const record of batch) {
        if (status === undefined || publicStatus(record.status) === status) {
          matched.push(record);
          if (matched.length === pageSize) break;
        }
      }
      const last = batch[batch.length - 1];
      position = { at: last.createdAt, id: last.id };
      if (batch.length < pageSize) break;
    }

    const items = matched.slice(0, limit);
    const display = await this.deps.display.describe(items);
    return {
      items: items.map((record) => {
        const shown = display.get(record.id);
        return toCommissionView(record, {
          referralDisplayName:
            shown?.referralDisplayName ?? UNKNOWN_REFERRAL_DISPLAY_NAME,
          planName: shown?.planName ?? UNKNOWN_PLAN_NAME,
        });
      }),
      nextCursor:
        matched.length > limit
          ? encodeCursor(
              items[items.length - 1].createdAt,
              items[items.length - 1].id,
            )
          : null,
    };
  }

  /** GET /agent/balance. */
  async getBalance(claims: AgentAccessClaims): Promise<AgentBalance> {
    const agent = await this.deps.access.assertCan(claims, 'viewBalance');
    const parsed = parseAgentProgramSettings(
      await this.deps.settings.getMany([PAYOUT_MINIMUM_AMOUNT_PAISE_KEY]),
    );
    const minPayoutPaise = parsed.settings.payoutMinimumAmountPaise;
    if (minPayoutPaise === undefined) {
      throw new AgentConfigError([PAYOUT_MINIMUM_AMOUNT_PAISE_KEY]);
    }

    let onHoldPaise = 0;
    let after: PageCursor | undefined;
    for (;;) {
      const batch = await this.deps.commissions.listPage(
        { agentId: agent.id },
        { limit: BALANCE_SCAN_BATCH, after },
      );
      for (const record of batch) {
        if (publicStatus(record.status) === 'ON_HOLD') {
          onHoldPaise += record.amountPaise ?? 0;
        }
      }
      if (batch.length < BALANCE_SCAN_BATCH) break;
      const last = batch[batch.length - 1];
      after = { at: last.createdAt, id: last.id };
    }

    let paidPaise = 0;
    let payoutAfter: PageCursor | undefined;
    for (;;) {
      const batch = await this.deps.payouts.listPage(
        { agentId: agent.id, status: 'PAID' },
        { limit: BALANCE_SCAN_BATCH, after: payoutAfter },
      );
      for (const payout of batch) paidPaise += payout.amountPaise;
      if (batch.length < BALANCE_SCAN_BATCH) break;
      const last = batch[batch.length - 1];
      payoutAfter = { at: last.createdAt, id: last.id };
    }

    const availablePaise = Math.max(
      0,
      await this.deps.ledger.balance(agent.id),
    );
    return {
      onHoldPaise,
      availablePaise,
      paidPaise,
      minPayoutPaise,
      canRequestPayout: availablePaise >= minPayoutPaise,
    };
  }

  /** GET /agent/payouts: newest first, cursor paginated, read-only. */
  async listPayouts(
    claims: AgentAccessClaims,
    query: AgentMoneyQuery = {},
  ): Promise<AgentPage<AgentPayoutView>> {
    const agent = await this.deps.access.assertCan(claims, 'viewPayouts');
    const { limit, after } = parsePage(query);
    const rows = await this.deps.payouts.listPage(
      { agentId: agent.id },
      { limit: limit + 1, after },
    );
    const items = rows.slice(0, limit);
    const views = await Promise.all(
      items.map(async (payout) =>
        toPayoutView(
          payout,
          (await this.deps.commissions.listByPayout(payout.id)).length,
        ),
      ),
    );
    return {
      items: views,
      nextCursor:
        rows.length > limit
          ? encodeCursor(
              items[items.length - 1].createdAt,
              items[items.length - 1].id,
            )
          : null,
    };
  }

  /** POST /agent/devices: idempotent upsert on the token. */
  async registerDevice(
    claims: AgentAccessClaims,
    body: { fcmToken?: unknown; platform?: unknown },
  ): Promise<void> {
    const agent = await this.deps.access.assertCan(claims, 'registerDevice');
    const invalid: string[] = [];
    const token = body.fcmToken;
    if (
      typeof token !== 'string' ||
      token.length < FCM_TOKEN_MIN ||
      token.length > FCM_TOKEN_MAX
    ) {
      invalid.push('fcmToken');
    }
    if (!DEVICE_PLATFORMS.includes(body.platform as AgentDevicePlatform)) {
      invalid.push('platform');
    }
    if (invalid.length > 0) {
      throw new AgentServiceError('VALIDATION_FAILED', { fields: invalid });
    }
    await this.deps.devices.register({
      agentId: agent.id,
      fcmToken: token as string,
      platform: body.platform as AgentDevicePlatform,
    });
  }
}

function publicStatus(status: CommissionStatusValue): PublicCommissionStatus {
  // Unknown values fail safe to ON_HOLD, as in toPublicCommissionStatus.
  return COMMISSION_STATUS_PUBLIC_MAP[status] ?? 'ON_HOLD';
}

function istDateOrNull(value: Date | null): string | null {
  return value === null ? null : toIstDate(value);
}

export function toCommissionView(
  record: CommissionRecord,
  shown: { referralDisplayName: string; planName: string },
): AgentCommissionView {
  const status = publicStatus(record.status);
  return {
    id: record.id,
    referralId: record.attributionId,
    referralDisplayName: shown.referralDisplayName,
    planName: shown.planName,
    basePaise: record.basePaise ?? 0,
    amountPaise: record.amountPaise ?? 0,
    rate: { calcType: record.calcType, value: record.ruleValue },
    status,
    earnedOn: toIstDate(record.createdAt),
    holdEndsOn: status === 'CANCELLED' ? null : toIstDate(record.holdUntil),
    approvedOn: istDateOrNull(record.approvedAt),
    paidOn: istDateOrNull(record.paidAt),
  };
}

export function toPayoutView(
  payout: AgentPayoutRecord,
  commissionCount: number,
): AgentPayoutView {
  return {
    id: payout.id,
    amountPaise: payout.amountPaise,
    status: payout.status,
    reference: payout.status === 'PAID' ? payout.reference : null,
    createdOn: toIstDate(payout.createdAt),
    paidOn: istDateOrNull(payout.paidAt),
    commissionCount,
  };
}

function parsePublicStatus(
  status: string | undefined,
): PublicCommissionStatus | undefined {
  if (status === undefined) return undefined;
  if (PUBLIC_STATUSES.includes(status as PublicCommissionStatus)) {
    return status as PublicCommissionStatus;
  }
  throw new AgentServiceError('VALIDATION_FAILED', { fields: ['status'] });
}

function parsePage(query: AgentMoneyQuery): {
  limit: number;
  after: PageCursor | undefined;
} {
  const invalid: string[] = [];
  let limit = DEFAULT_MONEY_PAGE_LIMIT;
  if (query.limit !== undefined) {
    if (
      !Number.isSafeInteger(query.limit) ||
      query.limit < 1 ||
      query.limit > MAX_MONEY_PAGE_LIMIT
    ) {
      invalid.push('limit');
    } else {
      limit = query.limit;
    }
  }
  let after: PageCursor | undefined;
  if (query.cursor !== undefined) {
    after = decodeCursor(query.cursor);
    if (after === undefined) invalid.push('cursor');
  }
  if (invalid.length > 0) {
    throw new AgentServiceError('VALIDATION_FAILED', { fields: invalid });
  }
  return { limit, after };
}

/** Opaque to clients: base64url of { t: ISO time, i: id }. */
function encodeCursor(at: Date, id: string): string {
  return Buffer.from(JSON.stringify({ t: at.toISOString(), i: id })).toString(
    'base64url',
  );
}

function decodeCursor(cursor: string): PageCursor | undefined {
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
