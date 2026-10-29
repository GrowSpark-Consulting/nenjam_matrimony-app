import { ApiPropertyOptional, ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsArray,
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  Length,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

const PLAN_CODES = ['FREE', 'SILVER', 'GOLD', 'PLATINUM'] as const;
const SUBSCRIPTION_STATUSES = [
  'ACTIVE',
  'EXPIRED',
  'CANCELLED',
  'PENDING',
] as const;
const DRAFT_STATUSES = [
  'DRAFT',
  'SUBMITTED',
  'PUBLISHED',
  'REJECTED',
  'DISCARDED',
] as const;

/** Every sensitive change carries one; stored on the audit row. */
export class AdminReasonDto {
  @ApiProperty({ description: 'Why — kept in the audit log.' })
  @IsString()
  @Length(3, 500)
  reason!: string;
}

export class PlanDisplayDto extends AdminReasonDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @Length(2, 60)
  displayName?: string;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(1000)
  displayOrder?: number;
}

export class PlanStatusDto extends AdminReasonDto {
  @ApiProperty({
    description: 'false stops new sales; existing subscriptions are untouched.',
  })
  @IsBoolean()
  isActive!: boolean;
}

export class CreatePlanDraftDto {
  @ApiProperty({ enum: PLAN_CODES })
  @IsIn(PLAN_CODES)
  planCode!: (typeof PLAN_CODES)[number];

  @ApiProperty({ description: 'What this change is for.' })
  @IsString()
  @Length(3, 500)
  changeNote!: string;
}

export class UpdatePlanDraftDto {
  @ApiPropertyOptional({
    description: 'The complete entitlement map (every feature).',
  })
  @IsOptional()
  @IsObject()
  entitlements?: Record<string, unknown>;

  @ApiPropertyOptional({
    description:
      'The complete price list: [{ months, durationDays, bonusDays, priceInPaise, isActive }]. Prices are integer paise.',
  })
  @IsOptional()
  @IsArray()
  durations?: unknown[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @Length(3, 500)
  changeNote?: string;
}

export class PublishPlanDraftDto {
  @ApiPropertyOptional({ description: 'Optional approval note.' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

export class PlanDraftQueryDto {
  @ApiPropertyOptional({ enum: PLAN_CODES })
  @IsOptional()
  @IsIn(PLAN_CODES)
  planCode?: (typeof PLAN_CODES)[number];

  @ApiPropertyOptional({ enum: DRAFT_STATUSES })
  @IsOptional()
  @IsIn(DRAFT_STATUSES)
  status?: (typeof DRAFT_STATUSES)[number];
}

class PageQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  cursor?: string;

  @ApiPropertyOptional({ minimum: 1, maximum: 100, default: 25 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}

export class SubscriptionQueryDto extends PageQueryDto {
  @ApiPropertyOptional({
    description:
      'Exact member email, phone (+91…), user id or subscription id.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(254)
  q?: string;

  @ApiPropertyOptional({ enum: SUBSCRIPTION_STATUSES })
  @IsOptional()
  @IsIn(SUBSCRIPTION_STATUSES)
  status?: (typeof SUBSCRIPTION_STATUSES)[number];

  @ApiPropertyOptional({ enum: PLAN_CODES })
  @IsOptional()
  @IsIn(PLAN_CODES)
  planCode?: (typeof PLAN_CODES)[number];
}

export class ExtendSubscriptionDto extends AdminReasonDto {
  @ApiProperty({
    minimum: 1,
    maximum: 30,
    description:
      'Days to add. Longer extensions need a second approver (not built yet).',
  })
  @IsInt()
  @Min(1)
  @Max(30)
  days!: number;
}

export class AuditLogQueryDto extends PageQueryDto {
  @ApiPropertyOptional({
    description: 'Action prefix, e.g. "membership.plan".',
  })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  action?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  entity?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  entityId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  actorId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  to?: string;
}
