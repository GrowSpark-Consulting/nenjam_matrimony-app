import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import type { ReportReason } from '../../../../../../libs/database/generated/client';

export const REPORT_REASONS = [
  'FAKE_PROFILE',
  'INAPPROPRIATE_CONTENT',
  'HARASSMENT',
  'SPAM',
  'OTHER',
] as const;

/** Body for POST /users/:id/report. */
export class CreateReportDto {
  @ApiProperty({
    description: 'Reason for the report.',
    enum: REPORT_REASONS,
    example: 'FAKE_PROFILE',
  })
  @IsIn(REPORT_REASONS)
  reason!: ReportReason;

  @ApiPropertyOptional({
    description: 'Optional additional details for the moderator.',
    example: 'Photos look copied from another profile.',
    maxLength: 1000,
  })
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;
}
