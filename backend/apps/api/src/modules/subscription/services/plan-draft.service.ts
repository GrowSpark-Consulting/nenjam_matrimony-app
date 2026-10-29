import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  PlanDraftStatus,
  Prisma,
  SubscriptionPlanDraft,
  SubscriptionPlanName,
} from '../../../../../../libs/database/generated/client';
import type { AdminRequestContext } from '../../admin/auth/admin-request';
import { assertAdminPermission } from '../../admin/rbac/assert-admin-permission';
import { buildAuditRow } from '../../admin/services/admin-audit.service';
import { PlanCatalogService } from '../../entitlements/catalog/plan-catalog.service';
import type { CatalogPlan } from '../../entitlements/domain/membership.types';
import {
  reviewDraft,
  toDraftDuration,
  type DraftDuration,
  type DraftReview,
} from '../domain/plan-draft';
import { PlanCatalogAdminService } from './plan-catalog-admin.service';

export interface PlanDraftView {
  id: string;
  planCode: SubscriptionPlanName;
  planName: string;
  status: PlanDraftStatus;
  changeNote: string;
  entitlements: unknown;
  durations: DraftDuration[];
  baseVersion: number | null;
  currentVersion: number | null;
  /** True when the plan got a newer version after this draft was started —
   *  publishing it would overwrite that change, so it is refused. */
  stale: boolean;
  createdById: string;
  updatedById: string;
  submittedById: string | null;
  submittedAt: Date | null;
  decidedById: string | null;
  decidedAt: Date | null;
  decisionNote: string | null;
  publishedVersionId: string | null;
  createdAt: Date;
  updatedAt: Date;
  review: DraftReview;
}

interface Actor {
  actorId: string;
  context?: AdminRequestContext;
}

const OPEN: PlanDraftStatus[] = ['DRAFT', 'SUBMITTED'];

/**
 * Changing what a plan grants or costs, with a second pair of eyes
 * (Admin Architecture v3: "plan version publish — second approver").
 *
 *   create (plan.edit) → edit (plan.edit) → submit (plan.edit)
 *     → publish (plan.publish, by a DIFFERENT admin) | reject (plan.publish)
 *   discard (plan.edit) while DRAFT or SUBMITTED.
 *
 * Publishing writes a new immutable version (when entitlements changed) and
 * the price list, in ONE transaction with the draft's status change and the
 * audit rows. Existing subscribers keep the version they bought.
 */
@Injectable()
export class PlanDraftService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly catalog: PlanCatalogService,
    private readonly catalogAdmin: PlanCatalogAdminService,
  ) {}

  async list(filter: {
    planCode?: SubscriptionPlanName;
    status?: PlanDraftStatus;
  }): Promise<PlanDraftView[]> {
    const rows = await this.prisma.subscriptionPlanDraft.findMany({
      where: {
        ...(filter.status && { status: filter.status }),
        ...(filter.planCode && { plan: { name: filter.planCode } }),
      },
      orderBy: { updatedAt: 'desc' },
      take: 100,
    });
    const { plans } = await this.catalog.getCatalog();
    return rows.map((row) => this.view(row, planById(plans, row.planId)));
  }

  async get(id: string): Promise<PlanDraftView> {
    const row = await this.requireDraft(id);
    const { plans } = await this.catalog.refresh();
    return this.view(row, planById(plans, row.planId));
  }

  /** Starts from the plan exactly as it is now. */
  async create(
    input: Actor & { planCode: SubscriptionPlanName; changeNote: string },
  ): Promise<PlanDraftView> {
    assertText(input.changeNote, 'changeNote');
    const plan = await this.catalogAdmin.requirePlan(input.planCode);
    const current = this.catalog.versionEffectiveAt(plan, new Date());
    const row = await this.prisma
      .$transaction(async (tx) => {
        await assertAdminPermission(tx, input.actorId, 'plan.edit');
        const created = await tx.subscriptionPlanDraft.create({
          data: {
            planId: plan.id,
            baseVersionId: current?.id ?? null,
            entitlements: (current?.entitlements ??
              {}) as unknown as Prisma.InputJsonValue,
            durations: plan.durations.map(
              toDraftDuration,
            ) as unknown as Prisma.InputJsonValue,
            changeNote: input.changeNote.trim(),
            createdById: input.actorId,
            updatedById: input.actorId,
          },
        });
        await this.audit(
          tx,
          input,
          'membership.plan.draft.create',
          created.id,
          {
            after: { plan: plan.code, baseVersion: current?.version ?? null },
          },
        );
        return created;
      })
      .catch((error: unknown) => {
        if ((error as { code?: string })?.code === 'P2002') {
          throw new ConflictException(
            `${plan.name} already has an open draft. Continue or discard that one first.`,
          );
        }
        throw error;
      });
    return this.view(row, plan);
  }

  /** Saves edits to a DRAFT. Anything may be saved half-finished; the
   *  review in the response says what still blocks publishing. */
  async update(
    input: Actor & {
      id: string;
      entitlements?: unknown;
      durations?: unknown;
      changeNote?: string;
    },
  ): Promise<PlanDraftView> {
    if (input.changeNote !== undefined)
      assertText(input.changeNote, 'changeNote');
    if (
      input.entitlements !== undefined &&
      !isPlainObject(input.entitlements)
    ) {
      throw new BadRequestException('entitlements must be an object.');
    }
    if (input.durations !== undefined && !Array.isArray(input.durations)) {
      throw new BadRequestException('durations must be a list.');
    }
    const row = await this.prisma.$transaction(async (tx) => {
      await assertAdminPermission(tx, input.actorId, 'plan.edit');
      const { count } = await tx.subscriptionPlanDraft.updateMany({
        where: { id: input.id, status: 'DRAFT' },
        data: {
          ...(input.entitlements !== undefined && {
            entitlements: input.entitlements as Prisma.InputJsonValue,
          }),
          ...(input.durations !== undefined && {
            durations: input.durations as Prisma.InputJsonValue,
          }),
          ...(input.changeNote !== undefined && {
            changeNote: input.changeNote.trim(),
          }),
          updatedById: input.actorId,
        },
      });
      if (count === 0)
        await this.refuseState(tx, input.id, 'edited', ['DRAFT']);
      await this.audit(tx, input, 'membership.plan.draft.update', input.id, {
        metadata: {
          changed: [
            ...(input.entitlements !== undefined ? ['entitlements'] : []),
            ...(input.durations !== undefined ? ['durations'] : []),
            ...(input.changeNote !== undefined ? ['changeNote'] : []),
          ],
        },
      });
      return tx.subscriptionPlanDraft.findUniqueOrThrow({
        where: { id: input.id },
      });
    });
    const { plans } = await this.catalog.getCatalog();
    return this.view(row, planById(plans, row.planId));
  }

  /** DRAFT → SUBMITTED, only when it would publish cleanly. */
  async submit(input: Actor & { id: string }): Promise<PlanDraftView> {
    const draft = await this.requireDraft(input.id);
    const plan = await this.freshPlanOf(draft.planId);
    this.assertPublishable(draft, plan);
    const row = await this.prisma.$transaction(async (tx) => {
      await assertAdminPermission(tx, input.actorId, 'plan.edit');
      const now = new Date();
      const { count } = await tx.subscriptionPlanDraft.updateMany({
        where: { id: input.id, status: 'DRAFT', updatedAt: draft.updatedAt },
        data: {
          status: 'SUBMITTED',
          submittedById: input.actorId,
          submittedAt: now,
        },
      });
      if (count === 0) {
        const latest = await tx.subscriptionPlanDraft.findUnique({
          where: { id: input.id },
          select: { status: true },
        });
        if (latest && latest.status !== 'DRAFT') {
          await this.refuseState(tx, input.id, 'submitted', ['DRAFT']);
        }
        throw new ConflictException(
          'The draft changed while you were submitting it. Review it again.',
        );
      }
      await this.audit(tx, input, 'membership.plan.draft.submit', input.id, {
        after: { plan: plan.code },
      });
      return tx.subscriptionPlanDraft.findUniqueOrThrow({
        where: { id: input.id },
      });
    });
    return this.view(row, plan);
  }

  /** SUBMITTED → PUBLISHED, by an admin other than the submitter. */
  async publish(
    input: Actor & { id: string; note?: string },
  ): Promise<PlanDraftView & { publishedVersion: number | null }> {
    const draft = await this.requireDraft(input.id);
    if (draft.status !== 'SUBMITTED') {
      throw new ConflictException(
        `Only a submitted draft can be published; this one is ${draft.status}.`,
      );
    }
    this.assertSecondAdmin(draft, input.actorId);
    const plan = await this.freshPlanOf(draft.planId);
    const review = this.assertPublishable(draft, plan);
    const now = new Date();

    let publishedVersion: number | null = null;
    let row: DraftRow;
    try {
      row = await this.prisma.$transaction(async (tx) => {
        await assertAdminPermission(tx, input.actorId, 'plan.publish');
        const { count } = await tx.subscriptionPlanDraft.updateMany({
          where: {
            id: draft.id,
            status: 'SUBMITTED',
            updatedAt: draft.updatedAt,
            NOT: { submittedById: input.actorId },
          },
          data: {
            status: 'PUBLISHED',
            decidedById: input.actorId,
            decidedAt: now,
            decisionNote: input.note?.trim() || null,
          },
        });
        if (count === 0) {
          throw new ConflictException(
            'The draft changed while you were publishing it. Review it again.',
          );
        }

        let versionId: string | null = null;
        if (review.changedFeatures.length > 0) {
          const result = await this.catalogAdmin.writeVersion(tx, plan, {
            entitlements: review.entitlements,
            effectiveFrom: now,
            changeNote: draft.changeNote,
            actorId: input.actorId,
            now,
          });
          versionId = result.versionId;
          publishedVersion = result.version;
        }
        for (const change of review.durationChanges) {
          await this.catalogAdmin.writeDuration(tx, plan, {
            ...change.after,
            actorId: input.actorId,
            reason: `Plan draft ${draft.id}: ${draft.changeNote}`,
          });
        }
        await tx.subscriptionPlanDraft.update({
          where: { id: draft.id },
          data: { publishedVersionId: versionId },
        });
        await this.audit(tx, input, 'membership.plan.draft.publish', draft.id, {
          reason: input.note?.trim() || null,
          after: {
            plan: plan.code,
            submittedById: draft.submittedById,
            newVersion: publishedVersion,
            changedFeatures: review.changedFeatures,
            reductionsVsCurrent: review.reductionsVsCurrent,
            durationChanges: review.durationChanges.map((c) => ({
              months: c.months,
              before: c.before ? { ...c.before } : null,
              after: { ...c.after },
            })),
          },
        });
        return tx.subscriptionPlanDraft.findUniqueOrThrow({
          where: { id: draft.id },
        });
      });
    } finally {
      // Serve the new version and prices from this process immediately
      // (other replicas converge within the catalogue TTL).
      await this.catalogAdmin.refreshCatalog();
    }
    const fresh = await this.catalogAdmin.requirePlan(plan.code);
    return { ...this.view(row, fresh), publishedVersion };
  }

  /** SUBMITTED → REJECTED, with a reason, by an admin other than the
   *  submitter. */
  async reject(
    input: Actor & { id: string; reason: string },
  ): Promise<PlanDraftView> {
    assertText(input.reason, 'reason');
    const draft = await this.requireDraft(input.id);
    this.assertSecondAdmin(draft, input.actorId);
    const row = await this.prisma.$transaction(async (tx) => {
      await assertAdminPermission(tx, input.actorId, 'plan.publish');
      const { count } = await tx.subscriptionPlanDraft.updateMany({
        where: {
          id: input.id,
          status: 'SUBMITTED',
          NOT: { submittedById: input.actorId },
        },
        data: {
          status: 'REJECTED',
          decidedById: input.actorId,
          decidedAt: new Date(),
          decisionNote: input.reason.trim(),
        },
      });
      if (count === 0) {
        await this.refuseState(tx, input.id, 'rejected', ['SUBMITTED']);
      }
      await this.audit(tx, input, 'membership.plan.draft.reject', input.id, {
        reason: input.reason.trim(),
      });
      return tx.subscriptionPlanDraft.findUniqueOrThrow({
        where: { id: input.id },
      });
    });
    const { plans } = await this.catalog.getCatalog();
    return this.view(row, planById(plans, row.planId));
  }

  /** DRAFT or SUBMITTED → DISCARDED (the author withdrawing it). */
  async discard(
    input: Actor & { id: string; reason: string },
  ): Promise<PlanDraftView> {
    assertText(input.reason, 'reason');
    const row = await this.prisma.$transaction(async (tx) => {
      await assertAdminPermission(tx, input.actorId, 'plan.edit');
      const { count } = await tx.subscriptionPlanDraft.updateMany({
        where: { id: input.id, status: { in: OPEN } },
        data: { status: 'DISCARDED', updatedById: input.actorId },
      });
      if (count === 0) {
        await this.refuseState(tx, input.id, 'discarded', OPEN);
      }
      await this.audit(tx, input, 'membership.plan.draft.discard', input.id, {
        reason: input.reason.trim(),
      });
      return tx.subscriptionPlanDraft.findUniqueOrThrow({
        where: { id: input.id },
      });
    });
    const { plans } = await this.catalog.getCatalog();
    return this.view(row, planById(plans, row.planId));
  }

  // --------------------------------------------------------------------------

  private view(row: DraftRow, plan: CatalogPlan): PlanDraftView {
    const now = new Date();
    const current = this.catalog.versionEffectiveAt(plan, now);
    const base = row.baseVersionId
      ? plan.versions.find((v) => v.id === row.baseVersionId)
      : null;
    const reviewed = reviewDraft(plan, current, row);
    const open = OPEN.includes(row.status);
    const stale = open && (current?.id ?? null) !== row.baseVersionId;
    return {
      id: row.id,
      planCode: plan.code,
      planName: plan.name,
      status: row.status,
      changeNote: row.changeNote,
      entitlements: row.entitlements,
      durations: reviewed.durations,
      baseVersion: base?.version ?? null,
      currentVersion: current?.version ?? null,
      stale,
      createdById: row.createdById,
      updatedById: row.updatedById,
      submittedById: row.submittedById,
      submittedAt: row.submittedAt,
      decidedById: row.decidedById,
      decidedAt: row.decidedAt,
      decisionNote: row.decisionNote,
      publishedVersionId: row.publishedVersionId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      review: {
        entitlementProblems: reviewed.entitlementProblems,
        durationProblems: reviewed.durationProblems,
        changedFeatures: reviewed.changedFeatures,
        reductionsVsCurrent: reviewed.reductionsVsCurrent,
        durationChanges: reviewed.durationChanges,
        hasChanges: reviewed.hasChanges,
        publishable: reviewed.publishable && !stale,
      },
    };
  }

  private assertPublishable(draft: DraftRow, plan: CatalogPlan) {
    const current = this.catalog.versionEffectiveAt(plan, new Date());
    if ((current?.id ?? null) !== draft.baseVersionId) {
      throw new ConflictException(
        'The plan was changed after this draft was started. Discard it and start a new draft.',
      );
    }
    const review = reviewDraft(plan, current, draft);
    const problems = [
      ...review.entitlementProblems,
      ...review.durationProblems,
    ];
    if (problems.length > 0) {
      throw new BadRequestException({
        message: 'The draft is not valid yet.',
        problems,
      });
    }
    if (!review.hasChanges) {
      throw new BadRequestException(
        'The draft is the same as the current plan — there is nothing to publish.',
      );
    }
    return review;
  }

  private assertSecondAdmin(draft: DraftRow, actorId: string): void {
    if (draft.submittedById === actorId) {
      throw new ForbiddenException({
        statusCode: 403,
        error: 'Forbidden',
        code: 'PLAN_DRAFT_NEEDS_SECOND_ADMIN',
        message: 'A different admin must review this draft — you submitted it.',
      });
    }
  }

  private async requireDraft(id: string): Promise<DraftRow> {
    const row = await this.prisma.subscriptionPlanDraft.findUnique({
      where: { id },
    });
    if (!row) throw new NotFoundException('No plan draft with that id.');
    return row;
  }

  private async freshPlanOf(planId: string): Promise<CatalogPlan> {
    const { plans } = await this.catalog.refresh();
    return planById(plans, planId);
  }

  /** Throws the right error when a conditional update matched nothing. */
  private async refuseState(
    tx: Prisma.TransactionClient,
    id: string,
    verb: string,
    allowed: PlanDraftStatus[],
  ): Promise<never> {
    const row = await tx.subscriptionPlanDraft.findUnique({
      where: { id },
      select: { status: true },
    });
    if (!row) throw new NotFoundException('No plan draft with that id.');
    throw new ConflictException(
      `This draft is ${row.status}; only a ${allowed.join(' or ')} draft can be ${verb}.`,
    );
  }

  private async audit(
    tx: Prisma.TransactionClient,
    actor: Actor,
    action: string,
    draftId: string,
    extra: {
      reason?: string | null;
      after?: Prisma.InputJsonValue;
      metadata?: Prisma.InputJsonObject;
    },
  ): Promise<void> {
    await tx.auditLog.create({
      data: buildAuditRow({
        actorId: actor.actorId,
        actorType: 'STAFF',
        action,
        entity: 'SubscriptionPlanDraft',
        entityId: draftId,
        reason: extra.reason,
        after: extra.after,
        metadata: extra.metadata,
        context: actor.context,
      }),
    });
  }
}

type DraftRow = SubscriptionPlanDraft;

function planById(plans: CatalogPlan[], planId: string): CatalogPlan {
  const plan = plans.find((p) => p.id === planId);
  if (!plan) throw new NotFoundException('The draft’s plan no longer exists.');
  return plan;
}

function assertText(value: unknown, field: string): void {
  if (typeof value !== 'string' || value.trim().length < 3) {
    throw new BadRequestException(
      `${field} is required (at least 3 characters).`,
    );
  }
}

function isPlainObject(value: unknown): boolean {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
