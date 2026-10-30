/**
 * Bodies and queries of the remaining admin agent-program routes
 * (docs/agent-program/agent-admin-api.openapi.yaml). Shape only; the
 * services re-check content (reason length, amounts, periods).
 */
import { Transform, Type } from 'class-transformer';
import {
  ArrayMinSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';
import type {
  AgentPayoutStatusValue,
  CommissionStatusValue,
} from '../ports/agent-commission-ports';
import type { AgentAttributionStatus } from '../ports/agent-data-ports';
import type { RevealField } from './agent-admin.service';

const PERIOD = /^\d{4}-(0[1-9]|1[0-2])$/;

const toBoolean = ({ value }: { value: unknown }): unknown =>
  value === 'true' ? true : value === 'false' ? false : value;

class PageQuery {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}

export class AdminRevealDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayUnique()
  @IsIn(['PAN', 'PAYOUT_DETAILS', 'PHONE'], { each: true })
  fields!: RevealField[];

  @IsString()
  @Length(3, 500)
  reason!: string;
}

export class AdminAgentReferralsQueryDto extends PageQuery {
  @IsOptional()
  @IsIn(['ACTIVE', 'CONVERTED', 'EXPIRED', 'REJECTED'])
  status?: AgentAttributionStatus;

  @IsOptional()
  @Transform(toBoolean)
  @IsBoolean()
  needsReview?: boolean;
}

export class AdminReferralCorrectDto {
  @IsIn(['REASSIGN_AGENT', 'REJECT', 'CLEAR_REVIEW'])
  action!: 'REASSIGN_AGENT' | 'REJECT' | 'CLEAR_REVIEW';

  /** Required for REASSIGN_AGENT only. */
  @ValidateIf((o: AdminReferralCorrectDto) => o.action === 'REASSIGN_AGENT')
  @IsUUID()
  agentId?: string;

  @IsString()
  @Length(3, 500)
  reason!: string;
}

export class AdminCommissionsQueryDto extends PageQuery {
  @IsOptional()
  @IsIn([
    'ON_HOLD',
    'AWAITING_VERIFICATION',
    'IN_REVIEW',
    'FROZEN',
    'READY',
    'APPROVED',
    'PAID',
    'CANCELLED',
    'REVERSED',
  ])
  status?: CommissionStatusValue;

  @IsOptional()
  @IsUUID()
  agentId?: string;
}

export class AdminCommissionOverrideDto {
  @IsInt()
  @Min(0)
  amountPaise!: number;

  @IsString()
  @Length(3, 500)
  reason!: string;
}

export class AdminPayoutsQueryDto extends PageQuery {
  @IsOptional()
  @IsIn(['CREATED', 'PAID', 'CANCELLED'])
  status?: AgentPayoutStatusValue;

  @IsOptional()
  @IsUUID()
  agentId?: string;

  @IsOptional()
  @Matches(PERIOD)
  period?: string;
}

export class AdminPayoutCreateDto {
  @IsUUID()
  agentId!: string;

  @Matches(PERIOD)
  period!: string;

  @IsString()
  @Length(3, 500)
  reason!: string;
}

export class AdminPayoutMarkPaidDto {
  @IsString()
  @Length(1, 100)
  reference!: string;

  @IsDateString({ strict: true })
  paidAt!: string;

  @IsString()
  @Length(3, 500)
  reason!: string;
}
