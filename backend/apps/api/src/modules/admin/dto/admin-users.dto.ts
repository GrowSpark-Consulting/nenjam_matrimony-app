import { ApiPropertyOptional, ApiProperty } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Length,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export class AdminUserListQueryDto {
  @ApiPropertyOptional({ default: 1, minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({ default: 20, minimum: 1, maximum: 100 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 20;

  @ApiPropertyOptional({ description: 'Search by user ID, phone, email, or name' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  search?: string;

  @ApiPropertyOptional({ enum: ['MALE', 'FEMALE'] })
  @IsOptional()
  @IsIn(['MALE', 'FEMALE'])
  gender?: 'MALE' | 'FEMALE';

  @ApiPropertyOptional({ description: 'Filter by membership plan (e.g. FREE, GOLD, PLATINUM)' })
  @IsOptional()
  @IsString()
  membership?: string;

  @ApiPropertyOptional({
    enum: ['ACTIVE', 'BLOCKED', 'SUSPENDED', 'PENDING_VERIFICATION', 'DEACTIVATED', 'BANNED'],
  })
  @IsOptional()
  @IsIn(['ACTIVE', 'BLOCKED', 'SUSPENDED', 'PENDING_VERIFICATION', 'DEACTIVATED', 'BANNED'])
  status?: 'ACTIVE' | 'BLOCKED' | 'SUSPENDED' | 'PENDING_VERIFICATION' | 'DEACTIVATED' | 'BANNED';

  @ApiPropertyOptional({ description: 'Filter by profile completeness' })
  @IsOptional()
  @Transform(({ value }) => {
    if (value === 'true' || value === true) return true;
    if (value === 'false' || value === false) return false;
    return value;
  })
  @IsBoolean()
  profileComplete?: boolean;

  @ApiPropertyOptional({ description: 'Registration date start (ISO 8601)' })
  @IsOptional()
  @IsDateString()
  registeredFrom?: string;

  @ApiPropertyOptional({ description: 'Registration date end (ISO 8601)' })
  @IsOptional()
  @IsDateString()
  registeredTo?: string;

  @ApiPropertyOptional({ enum: ['createdAt', 'name', 'status'], default: 'createdAt' })
  @IsOptional()
  @IsIn(['createdAt', 'name', 'status'])
  sortBy?: 'createdAt' | 'name' | 'status' = 'createdAt';

  @ApiPropertyOptional({ enum: ['asc', 'desc'], default: 'desc' })
  @IsOptional()
  @IsIn(['asc', 'desc'])
  sortOrder?: 'asc' | 'desc' = 'desc';
}

export class BlockUserDto {
  @ApiProperty({ description: 'Mandatory reason for blocking the user' })
  @IsString()
  @Length(3, 500)
  reason!: string;
}

export class UnblockUserDto {
  @ApiPropertyOptional({ description: 'Optional reason for unblocking' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}

export class CreateMemberNoteDto {
  @ApiProperty({ description: 'Internal staff note content' })
  @IsString()
  @Length(1, 5000)
  note!: string;
}

export class RevealPiiDto {
  @ApiPropertyOptional({ description: 'Optional reason for unmasking PII (recorded in audit log)' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}

/** Alias for AdminUserListQueryDto to satisfy B-2 naming requirement */
export class AdminUserListDto extends AdminUserListQueryDto {}


