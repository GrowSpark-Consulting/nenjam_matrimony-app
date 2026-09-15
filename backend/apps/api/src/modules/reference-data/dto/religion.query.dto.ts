import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsOptional, IsString, Length, Matches } from 'class-validator';

/**
 * Codes are validated by shape here and then looked up — a code that passes
 * the regex but names nothing still 404s, so the regex is a cheap filter and
 * never the authority.
 *
 * Uppercasing on the way in means `?religionCode=hindu` works: clients should
 * not have to care about case, and the stored codes are canonical.
 */
export class ReligionsQueryDto {
  @ApiPropertyOptional({
    description:
      'Include religions no longer offered for new registrations. Only needed ' +
      'to resolve a code stored on an existing profile.',
    default: false,
  })
  @IsOptional()
  @Transform(({ value }: { value: unknown }) => value === true || value === 'true')
  includeInactive?: boolean = false;
}

export class CommunitiesQueryDto extends ReligionsQueryDto {
  @ApiProperty({ description: 'Religion code.', example: 'HINDU' })
  @IsString()
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toUpperCase() : value,
  )
  @Length(2, 20)
  @Matches(/^[A-Z0-9-]+$/, {
    message: 'religionCode must look like HINDU or INTER-RELIGION',
  })
  religionCode!: string;
}
