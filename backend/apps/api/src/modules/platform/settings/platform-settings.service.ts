import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { validationFailed } from '@app/common';
import { PrismaService } from '@app/database';
import { Prisma } from '../../../../../../libs/database/generated/client';
import type { AdminRequestContext } from '../../admin/auth/admin-request';
import { buildAuditRow } from '../../admin/services/admin-audit.service';

export interface PlatformSettingView {
  key: string;
  /** Stored JSON, unvalidated; `null` is a real value ("not decided"). */
  value: unknown;
  description: string | null;
  version: number;
  updatedAt: Date;
}

/** Returns a readable problem with [value], or null when it is acceptable. */
export type PlatformSettingValidator = (value: unknown) => string | null;

/** Stored values are small rules and numbers, never documents. */
const MAX_VALUE_JSON_LENGTH = 10_000;

/**
 * Platform settings: values operators tune without a release, one row per
 * key (`platform_settings`). Keys come from migrations only; this service
 * reads them and lets an admin change a value — versioned (the caller names
 * the version it read) and audited in the same transaction.
 *
 * Values are stored JSON and come back unvalidated: the code that reads a key
 * validates it. A feature can register a validator for its keys so a bad
 * value is refused when an admin enters it, not when it is next read.
 */
@Injectable()
export class PlatformSettingsService {
  private readonly validators = new Map<string, PlatformSettingValidator>();

  constructor(private readonly prisma: PrismaService) {}

  /**
   * The values of the requested keys that exist — never other keys, never an
   * invented default. A key set to JSON `null` is present, as `null`.
   */
  async getMany(keys: readonly string[]): Promise<Record<string, unknown>> {
    if (keys.length === 0) return {};
    const rows = await this.prisma.platformSetting.findMany({
      where: { key: { in: [...new Set(keys)] } },
      select: { key: true, value: true },
    });
    return Object.fromEntries(rows.map((row) => [row.key, row.value]));
  }

  async list(): Promise<PlatformSettingView[]> {
    const rows = await this.prisma.platformSetting.findMany({
      orderBy: { key: 'asc' },
    });
    return rows.map(toView);
  }

  /** Refuse bad values for [key] at entry. One validator per key. */
  registerValidator(key: string, validate: PlatformSettingValidator): void {
    if (this.validators.has(key)) {
      throw new Error(
        `A validator for setting "${key}" is already registered.`,
      );
    }
    this.validators.set(key, validate);
  }

  /**
   * Sets [key] to [value] if its version is still [expectedVersion]: 404 for
   * an unknown key, 409 when someone changed it since it was read, 400 for a
   * value its validator refuses. Writes `platform_setting.update` with the
   * old and new value in the same transaction.
   */
  async update(input: {
    key: string;
    value: unknown;
    expectedVersion: number;
    reason: string;
    actorId: string;
    context?: AdminRequestContext;
  }): Promise<PlatformSettingView> {
    const { key, value, expectedVersion } = input;
    this.checkValue(key, value);
    return this.prisma.$transaction(async (tx) => {
      const current = await tx.platformSetting.findUnique({ where: { key } });
      if (!current) {
        throw new NotFoundException({
          statusCode: 404,
          error: 'Not Found',
          code: 'SETTING_NOT_FOUND',
          message: `There is no setting "${key}".`,
        });
      }
      const changed = await tx.platformSetting.updateMany({
        where: { key, version: expectedVersion },
        data: {
          value:
            value === null ? Prisma.JsonNull : (value as Prisma.InputJsonValue),
          version: { increment: 1 },
          updatedAt: new Date(),
        },
      });
      if (changed.count === 0) {
        throw new ConflictException({
          statusCode: 409,
          error: 'Conflict',
          code: 'SETTING_VERSION_CONFLICT',
          message:
            'Someone changed this setting since you loaded it. Reload and try again.',
          currentVersion: current.version,
        });
      }
      const updated = await tx.platformSetting.findUniqueOrThrow({
        where: { key },
      });
      await tx.auditLog.create({
        data: buildAuditRow({
          actorId: input.actorId,
          actorType: 'STAFF',
          action: 'platform_setting.update',
          entity: 'PlatformSetting',
          entityId: key,
          reason: input.reason,
          before: { value: current.value, version: current.version },
          after: { value: updated.value, version: updated.version },
          context: input.context,
        }),
      });
      return toView(updated);
    });
  }

  private checkValue(key: string, value: unknown): void {
    if (value === undefined) {
      throw validationFailed(['value must be present (null is allowed)']);
    }
    if (JSON.stringify(value).length > MAX_VALUE_JSON_LENGTH) {
      throw validationFailed([
        `value must be at most ${MAX_VALUE_JSON_LENGTH} characters of JSON`,
      ]);
    }
    const problem = this.validators.get(key)?.(value) ?? null;
    if (problem) throw validationFailed([problem]);
  }
}

function toView(row: {
  key: string;
  value: Prisma.JsonValue;
  description: string | null;
  version: number;
  updatedAt: Date;
}): PlatformSettingView {
  return {
    key: row.key,
    value: row.value,
    description: row.description,
    version: row.version,
    updatedAt: row.updatedAt,
  };
}
