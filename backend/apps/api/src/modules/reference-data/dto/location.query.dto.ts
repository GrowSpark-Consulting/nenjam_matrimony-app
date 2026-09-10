import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsInt, IsOptional, IsString, Length, Matches, Max, Min } from 'class-validator';

/**
 * Codes arrive from the client as path-safe strings. They are validated by
 * shape here and then looked up — a code that passes the regex but names
 * nothing still 404s, so the regex is a cheap filter, never the authority.
 *
 * Uppercasing on the way in means `?countryCode=in` works: members' clients
 * should not have to care about case, and the stored codes are canonical.
 */
const upper = () =>
  Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toUpperCase() : value,
  );

export class CountriesQueryDto {
  @ApiPropertyOptional({
    description:
      'Include countries that are no longer offered for new registrations. ' +
      'Only needed to resolve a code stored on an existing profile.',
    default: false,
  })
  @IsOptional()
  @Transform(({ value }: { value: unknown }) => value === true || value === 'true')
  includeInactive?: boolean = false;
}

export class StatesQueryDto extends CountriesQueryDto {
  @ApiProperty({ description: 'ISO 3166-1 alpha-2 country code.', example: 'IN' })
  @IsString()
  @upper()
  @Length(2, 2)
  @Matches(/^[A-Z]{2}$/, { message: 'countryCode must be two letters, e.g. IN' })
  countryCode!: string;
}

export class CitiesQueryDto extends CountriesQueryDto {
  @ApiProperty({ description: 'ISO 3166-2 subdivision code.', example: 'IN-TN' })
  @IsString()
  @upper()
  @Length(4, 6)
  @Matches(/^[A-Z]{2}-[A-Z0-9]{1,3}$/, {
    message: 'stateCode must look like IN-TN',
  })
  stateCode!: string;

  @ApiPropertyOptional({
    description:
      'Case-insensitive prefix/substring filter on the city name, for type-ahead.',
    example: 'chen',
  })
  @IsOptional()
  @IsString()
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @Length(1, 60)
  search?: string;

  @ApiPropertyOptional({
    description: 'Maximum cities to return, largest first.',
    default: 200,
    maximum: 1000,
  })
  @IsOptional()
  @Transform(({ value }: { value: unknown }) => (value === undefined ? undefined : Number(value)))
  @IsInt()
  @Min(1)
  @Max(1000)
  limit?: number = 200;
}
