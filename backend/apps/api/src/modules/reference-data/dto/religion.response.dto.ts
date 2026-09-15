import { ApiProperty } from '@nestjs/swagger';

/// What the client needs: a code to store and a label to show. Deliberately
/// not the Prisma row — `isActive` is a filter the server has already applied
/// and the timestamps are bookkeeping, so leaving them out means a future
/// column cannot leak by accident.
export class ReligionDto {
  @ApiProperty({ example: 'HINDU', description: 'Stable code for this religion.' })
  code!: string;

  @ApiProperty({ example: 'Hindu' })
  label!: string;
}

export class CommunityDto {
  @ApiProperty({
    example: 'HINDU-VELLALAR',
    description: 'Deterministic code: religion code + normalized community name.',
  })
  code!: string;

  @ApiProperty({ example: 'Vellalar' })
  label!: string;

  @ApiProperty({ example: 'HINDU' })
  religionCode!: string;
}
