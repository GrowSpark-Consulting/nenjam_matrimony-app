import { ApiProperty } from '@nestjs/swagger';

/**
 * What the client actually needs: a code to store and a label to show.
 *
 * Deliberately not the Prisma row. `createdAt` / `updatedAt` are bookkeeping,
 * and `population` is an ordering input the server has already applied — none
 * of it belongs on the wire, and leaving it out means a future column cannot
 * leak by accident.
 */
export class CountryDto {
  @ApiProperty({ example: 'IN', description: 'ISO 3166-1 alpha-2 code.' })
  code!: string;

  @ApiProperty({ example: 'India' })
  label!: string;
}

export class SubdivisionDto extends CountryDto {
  @ApiProperty({ example: 'IN-TN', description: 'ISO 3166-2 code.' })
  declare code: string;

  @ApiProperty({ example: 'Tamil Nadu' })
  declare label: string;

  @ApiProperty({
    example: 'State',
    description: "ISO's own wording — State, Union territory, Province, City-state.",
  })
  type!: string;

  @ApiProperty({ example: 'IN' })
  countryCode!: string;
}

export class CityDto {
  @ApiProperty({
    example: 'IN-TN-CHENNAI',
    description: 'Deterministic code: subdivision code + normalized name.',
  })
  code!: string;

  @ApiProperty({ example: 'Chennai' })
  label!: string;

  @ApiProperty({ example: 'IN-TN' })
  stateCode!: string;

  @ApiProperty({ example: 'IN' })
  countryCode!: string;
}
