import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Length,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import type { AgentStatus } from '../agent/agent-status';

const AGENT_STATUSES: AgentStatus[] = [
  'PENDING_APPROVAL',
  'ACTIVE',
  'REJECTED',
  'SUSPENDED',
  'TERMINATED',
];

/** `GET /admin/agents` query (the contract's filters; page size 1 to 100, default 25). */
export class AdminAgentsQueryDto {
  @IsOptional()
  @IsIn(AGENT_STATUSES)
  status?: AgentStatus;

  /** An exact agent id, a referral code (NM...), a full E.164 phone, or a name prefix. */
  @IsOptional()
  @IsString()
  @MaxLength(64)
  q?: string;

  /** Case-insensitive prefix of the agent's name. */
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  name?: string;

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

/** `{ reason }`, 3 to 500 characters (the contract's `Reason`). */
export class AdminAgentReasonDto {
  @IsString()
  @Length(3, 500)
  reason!: string;
}
