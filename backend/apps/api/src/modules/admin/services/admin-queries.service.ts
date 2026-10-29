import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '@app/database';
import { maskEmailForDisplay } from '@app/mail';
import type {
  Prisma,
  SubscriptionPlanName,
  SubscriptionStatus,
} from '../../../../../../libs/database/generated/client';
import { maskPhone } from '../../agents/referral/agent-referral-view';
import { FEATURE_KEYS } from '../../entitlements/catalog/feature-catalog';
import { PlanCatalogService } from '../../entitlements/catalog/plan-catalog.service';
import { describeFeature } from '../../subscription/services/plans.service';
import type { PermissionKey } from '../rbac/permissions';

/** A page of results; `nextCursor` is null on the last page. */
export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

export interface MemberSummary {
  userId: string;
  /** Masked (`pr***@gmail.com`); null for phone-only accounts. */
  email: string | null;
  /** Masked (`+91 98***210`); null when none. */
  phone: string | null;
  /** First name and last initial, when the member has a profile. */
  name: string | null;
}

const MAX_PAGE = 100;
const DEFAULT_PAGE = 25;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Read side of the admin panel: catalogue, subscriptions, audit log, overview
 * and roles. Read-only by construction — every write goes through the domain
 * services, which check permissions and audit in their own transaction.
 * Member contact details are always masked here.
 */
@Injectable()
export class AdminQueriesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly catalog: PlanCatalogService,
  ) {}

  // --- Plans -----------------------------------------------------------------

  async plans() {
    const now = new Date();
    const { plans } = await this.catalog.refresh();
    const [versionRows, openDrafts, activeCounts] = await Promise.all([
      this.prisma.subscriptionPlanVersion.findMany({
        select: {
          id: true,
          planId: true,
          version: true,
          effectiveFrom: true,
          changeNote: true,
          createdById: true,
          createdAt: true,
        },
        orderBy: [{ planId: 'asc' }, { version: 'desc' }],
      }),
      this.prisma.subscriptionPlanDraft.findMany({
        where: { status: { in: ['DRAFT', 'SUBMITTED'] } },
        select: { id: true, planId: true, status: true },
      }),
      this.prisma.userSubscription.groupBy({
        by: ['planId'],
        where: { status: 'ACTIVE', endDate: { gt: now } },
        _count: { _all: true },
      }),
    ]);
    return {
      plans: plans.map((plan) => {
        const current = this.catalog.versionEffectiveAt(plan, now);
        const draft = openDrafts.find((d) => d.planId === plan.id);
        return {
          code: plan.code,
          name: plan.name,
          description: plan.description,
          tier: plan.tier,
          displayOrder: plan.displayOrder,
          isActive: plan.isActive,
          isFree: plan.code === 'FREE',
          activeSubscribers:
            activeCounts.find((c) => c.planId === plan.id)?._count._all ?? 0,
          currentVersion: current
            ? {
                id: current.id,
                version: current.version,
                effectiveFrom: current.effectiveFrom,
                entitlements: current.entitlements,
                problems: current.problems,
              }
            : null,
          versions: versionRows
            .filter((v) => v.planId === plan.id)
            .map((v) => ({
              id: v.id,
              version: v.version,
              effectiveFrom: v.effectiveFrom,
              changeNote: v.changeNote,
              createdById: v.createdById,
              createdAt: v.createdAt,
              isCurrent: v.id === current?.id,
              isScheduled: v.effectiveFrom > now,
            })),
          durations: plan.durations,
          openDraft: draft ? { id: draft.id, status: draft.status } : null,
        };
      }),
      features: FEATURE_KEYS.map(describeFeature),
    };
  }

  // --- Subscriptions ---------------------------------------------------------

  async subscriptions(filter: {
    q?: string;
    status?: SubscriptionStatus;
    planCode?: SubscriptionPlanName;
    cursor?: string;
    limit?: number;
  }): Promise<Page<SubscriptionRow>> {
    const limit = pageSize(filter.limit);
    const cursor = decodeCursor(filter.cursor);
    const where: Prisma.UserSubscriptionWhereInput = {
      ...(filter.status && { status: filter.status }),
      ...(filter.planCode && { plan: { name: filter.planCode } }),
      ...(filter.q && memberMatch(filter.q)),
      ...(cursor && {
        OR: [
          { createdAt: { lt: cursor.at } },
          { createdAt: cursor.at, id: { lt: cursor.id } },
        ],
      }),
    };
    const rows = await this.prisma.userSubscription.findMany({
      where,
      select: SUBSCRIPTION_SELECT,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    return page(rows, limit, toSubscriptionRow);
  }

  async subscription(id: string) {
    const row = await this.prisma.userSubscription.findUnique({
      where: { id },
      select: {
        ...SUBSCRIPTION_SELECT,
        autoRenew: true,
        activatedAt: true,
        planVersion: { select: { version: true } },
        events: {
          select: {
            id: true,
            type: true,
            fromStatus: true,
            toStatus: true,
            actorId: true,
            metadata: true,
            createdAt: true,
          },
          orderBy: { createdAt: 'asc' },
        },
        payments: {
          select: {
            id: true,
            razorpayOrderId: true,
            razorpayPaymentId: true,
            amountInr: true,
            currency: true,
            status: true,
            paidAt: true,
            failureReason: true,
            refundedAmount: true,
            refundedAt: true,
            createdAt: true,
          },
          orderBy: { createdAt: 'desc' },
        },
      },
    });
    if (!row) throw new NotFoundException('No subscription with that id.');
    return {
      ...toSubscriptionRow(row),
      autoRenew: row.autoRenew,
      activatedAt: row.activatedAt,
      planVersion: row.planVersion?.version ?? null,
      events: row.events,
      payments: row.payments.map(({ amountInr, ...payment }) => ({
        ...payment,
        amountInPaise: amountInr,
      })),
    };
  }

  // --- Audit log -------------------------------------------------------------

  async auditLogs(filter: {
    action?: string;
    entity?: string;
    entityId?: string;
    actorId?: string;
    from?: Date;
    to?: Date;
    cursor?: string;
    limit?: number;
  }) {
    const limit = pageSize(filter.limit);
    const cursor = decodeCursor(filter.cursor);
    const rows = await this.prisma.auditLog.findMany({
      where: {
        ...(filter.action && { action: { startsWith: filter.action } }),
        ...(filter.entity && { entity: filter.entity }),
        ...(filter.entityId && { entityId: filter.entityId }),
        ...(filter.actorId && { actorId: filter.actorId }),
        ...((filter.from || filter.to) && {
          createdAt: {
            ...(filter.from && { gte: filter.from }),
            ...(filter.to && { lte: filter.to }),
          },
        }),
        ...(cursor && {
          OR: [
            { createdAt: { lt: cursor.at } },
            { createdAt: cursor.at, id: { lt: cursor.id } },
          ],
        }),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const actorIds = [
      ...new Set(rows.map((r) => r.actorId).filter((id): id is string => !!id)),
    ];
    const actors = await this.prisma.user.findMany({
      where: { id: { in: actorIds } },
      select: { id: true, email: true, role: true },
    });
    return page(rows, limit, (row) => {
      const actor = actors.find((a) => a.id === row.actorId);
      return {
        id: row.id,
        createdAt: row.createdAt,
        actorId: row.actorId,
        // Staff are named; a member actor is masked like everywhere else.
        actor: actor
          ? actor.role === 'USER'
            ? maskedEmail(actor.email)
            : actor.email
          : row.actorId
            ? null
            : 'system',
        action: row.action,
        entity: row.entity,
        entityId: row.entityId,
        reason: row.reason,
        before: row.before,
        after: row.after,
        metadata: row.metadata,
        requestId: row.requestId,
        ipAddress: row.ipAddress,
      };
    });
  }

  // --- Overview --------------------------------------------------------------

  async overview(permissions: readonly PermissionKey[]) {
    const now = new Date();
    const since = new Date(now.getTime() - 30 * 24 * 3600 * 1000);
    const [members, activeByPlan, drafts, revenue] = await Promise.all([
      this.prisma.user.groupBy({
        by: ['status'],
        where: { role: 'USER', deletedAt: null },
        _count: { _all: true },
      }),
      this.prisma.userSubscription.groupBy({
        by: ['planId'],
        where: { status: 'ACTIVE', endDate: { gt: now } },
        _count: { _all: true },
      }),
      this.prisma.subscriptionPlanDraft.groupBy({
        by: ['status'],
        where: { status: { in: ['DRAFT', 'SUBMITTED'] } },
        _count: { _all: true },
      }),
      permissions.includes('finance.view')
        ? this.prisma.paymentTransaction.aggregate({
            where: { status: 'SUCCESS', paidAt: { gte: since } },
            _sum: { amountInr: true, refundedAmount: true },
            _count: { _all: true },
          })
        : null,
    ]);
    const { plans } = await this.catalog.getCatalog(now);
    return {
      generatedAt: now,
      members: {
        total: members.reduce((sum, m) => sum + m._count._all, 0),
        byStatus: Object.fromEntries(
          members.map((m) => [m.status, m._count._all]),
        ),
      },
      activeSubscriptions: plans
        .filter((p) => p.code !== 'FREE')
        .map((p) => ({
          planCode: p.code,
          planName: p.name,
          count: activeByPlan.find((a) => a.planId === p.id)?._count._all ?? 0,
        })),
      planDrafts: {
        open: drafts.find((d) => d.status === 'DRAFT')?._count._all ?? 0,
        awaitingApproval:
          drafts.find((d) => d.status === 'SUBMITTED')?._count._all ?? 0,
      },
      // Only for admins holding finance.view; null otherwise.
      revenueLast30Days: revenue
        ? {
            payments: revenue._count._all,
            grossInPaise: revenue._sum.amountInr ?? 0,
            refundedInPaise: revenue._sum.refundedAmount ?? 0,
          }
        : null,
    };
  }

  // --- Roles -----------------------------------------------------------------

  async roles() {
    const [roles, permissions] = await Promise.all([
      this.prisma.role.findMany({
        select: {
          key: true,
          name: true,
          description: true,
          isSystem: true,
          permissions: { select: { permission: { select: { key: true } } } },
          admins: {
            select: {
              adminAccount: {
                select: {
                  isActive: true,
                  mfaEnrolledAt: true,
                  lastLoginAt: true,
                  user: { select: { email: true } },
                },
              },
            },
          },
        },
        orderBy: { key: 'asc' },
      }),
      this.prisma.permission.findMany({
        select: { key: true, description: true, isSensitive: true },
        orderBy: { key: 'asc' },
      }),
    ]);
    return {
      roles: roles.map((role) => ({
        key: role.key,
        name: role.name,
        description: role.description,
        isSystem: role.isSystem,
        permissions: role.permissions.map((p) => p.permission.key).sort(),
        admins: role.admins.map(({ adminAccount: a }) => ({
          email: a.user.email,
          active: a.isActive,
          authenticatorEnrolled: a.mfaEnrolledAt !== null,
          lastLoginAt: a.lastLoginAt,
        })),
      })),
      permissions,
    };
  }
}

// ----------------------------------------------------------------------------

const SUBSCRIPTION_SELECT = {
  id: true,
  status: true,
  source: true,
  startDate: true,
  endDate: true,
  priceInPaise: true,
  currency: true,
  cancelledAt: true,
  cancellationReason: true,
  createdAt: true,
  plan: { select: { name: true, displayName: true } },
  duration: { select: { months: true } },
  user: {
    select: {
      id: true,
      email: true,
      phone: true,
      profile: { select: { firstName: true, lastName: true } },
    },
  },
  payments: {
    select: { status: true, amountInr: true, paidAt: true },
    orderBy: { createdAt: 'desc' },
    take: 1,
  },
} satisfies Prisma.UserSubscriptionSelect;

type SubscriptionRecord = Prisma.UserSubscriptionGetPayload<{
  select: typeof SUBSCRIPTION_SELECT;
}>;

export type SubscriptionRow = ReturnType<typeof toSubscriptionRow>;

function toSubscriptionRow(row: SubscriptionRecord) {
  const last = row.payments[0];
  return {
    id: row.id,
    status: row.status,
    source: row.source,
    plan: { code: row.plan.name, name: row.plan.displayName },
    months: row.duration?.months ?? null,
    startDate: row.startDate,
    endDate: row.endDate,
    priceInPaise: row.priceInPaise,
    currency: row.currency,
    cancelledAt: row.cancelledAt,
    cancellationReason: row.cancellationReason,
    createdAt: row.createdAt,
    member: memberSummary(row.user),
    lastPayment: last
      ? {
          status: last.status,
          amountInPaise: last.amountInr,
          paidAt: last.paidAt,
        }
      : null,
  };
}

export function memberSummary(user: {
  id: string;
  email: string;
  phone: string | null;
  profile: { firstName: string; lastName: string } | null;
}): MemberSummary {
  const first = user.profile?.firstName.trim();
  const last = user.profile?.lastName.trim();
  return {
    userId: user.id,
    email: maskedEmail(user.email),
    phone: user.phone ? maskPhone(user.phone) : null,
    name: first ? (last ? `${first} ${[...last][0]}.` : first) : null,
  };
}

/** Phone-only accounts carry a synthetic `<uid>@firebase.invalid` address,
 *  which is not the member's and is not shown. */
function maskedEmail(email: string): string | null {
  return email.endsWith('@firebase.invalid')
    ? null
    : maskEmailForDisplay(email);
}

/**
 * Members are looked up by an exact identifier, never by partial text: an
 * email, an E.164 phone, or a user/subscription id.
 */
function memberMatch(raw: string): Prisma.UserSubscriptionWhereInput {
  const q = raw.trim();
  if (q.includes('@')) return { user: { email: q.toLowerCase() } };
  const phone = q.replace(/[\s-]/g, '');
  if (/^\+[1-9]\d{7,14}$/.test(phone)) return { user: { phone } };
  if (UUID.test(q)) return { AND: [{ OR: [{ id: q }, { userId: q }] }] };
  throw new BadRequestException(
    'Search by the member’s exact email, phone (+91…) or user / subscription id.',
  );
}

function pageSize(limit: number | undefined): number {
  if (limit === undefined) return DEFAULT_PAGE;
  return Math.min(Math.max(Math.trunc(limit), 1), MAX_PAGE);
}

function page<R extends { id: string; createdAt: Date }, T>(
  rows: R[],
  limit: number,
  map: (row: R) => T,
): Page<T> {
  const items = rows.slice(0, limit);
  const last = items[items.length - 1];
  return {
    items: items.map(map),
    nextCursor:
      rows.length > limit && last
        ? Buffer.from(`${last.createdAt.toISOString()}|${last.id}`).toString(
            'base64url',
          )
        : null,
  };
}

function decodeCursor(cursor: string | undefined) {
  if (!cursor) return null;
  const [iso, id] = Buffer.from(cursor, 'base64url')
    .toString('utf8')
    .split('|');
  const at = new Date(iso);
  if (!id || Number.isNaN(at.getTime())) {
    throw new BadRequestException('Invalid cursor.');
  }
  return { at, id };
}
