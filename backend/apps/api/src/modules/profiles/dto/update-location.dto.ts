import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsInt,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  Min,
} from 'class-validator';

/**
 * Body of PUT /profiles/me/location — the caller's own device coordinates,
 * written after they grant OS location permission.
 *
 * Only ever writes the AUTHENTICATED caller's row (the route takes the user id
 * from the verified Firebase token, never from the body), so there is no
 * userId field here to spoof.
 */
export class UpdateLocationDto {
  @ApiProperty({ description: 'Device latitude, -90..90.', example: 13.0827 })
  @Type(() => Number)
  @IsNumber()
  @IsLatitude()
  latitude!: number;

  @ApiProperty({
    description: 'Device longitude, -180..180.',
    example: 80.2707,
  })
  @Type(() => Number)
  @IsNumber()
  @IsLongitude()
  longitude!: number;

  @ApiPropertyOptional({
    description:
      'Accuracy radius in metres as reported by the device. Coarse ("Approximate") fixes report 1000-3000; precise fixes report tens of metres.',
    example: 25,
    minimum: 0,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  accuracyM?: number;
}

/** What the caller gets back after storing a location. Echoes their own
 *  coordinates — their own location is not a secret from them — plus the
 *  server-side timestamp, so the client can decide when its fix is stale. */
export interface LocationResponseDto {
  latitude: number;
  longitude: number;
  accuracyM: number | null;
  updatedAt: string;
}
