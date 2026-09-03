import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsInt,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  Max,
  Min,
} from 'class-validator';
import { DiscoverProfileDto } from './discover-profile.response.dto';

/**
 * Hard ceiling on the search radius, in kilometres.
 *
 * Enforced by validation rather than silently clamped: a client asking for
 * 500km has a bug or is probing, and both are better answered with a 400 than
 * with quietly different results than requested. It also bounds the worst-case
 * bounding box, which is what keeps the prefilter from degenerating into a
 * full table scan.
 */
export const MAX_RADIUS_KM = 100;

/** Radius applied when the caller does not ask for one. */
export const DEFAULT_RADIUS_KM = 100;

/**
 * Query parameters for GET /profiles/nearby.
 *
 * The global ValidationPipe runs with `transform: true` and
 * `forbidNonWhitelisted: true`, so every field needs `@Type(() => Number)` to
 * survive arriving as a query string, and an unknown parameter is a 400 rather
 * than being ignored.
 */
export class NearbyQueryDto {
  @ApiPropertyOptional({
    description:
      'Caller latitude. Optional — falls back to the location last stored via PUT /profiles/me/location.',
    example: 13.0827,
  })
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @IsLatitude()
  latitude?: number;

  @ApiPropertyOptional({
    description:
      'Caller longitude. Optional — falls back to the location last stored via PUT /profiles/me/location.',
    example: 80.2707,
  })
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @IsLongitude()
  longitude?: number;

  @ApiPropertyOptional({
    description: 'Search radius in kilometres.',
    default: DEFAULT_RADIUS_KM,
    minimum: 1,
    maximum: MAX_RADIUS_KM,
  })
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  @Max(MAX_RADIUS_KM)
  radiusKm?: number = DEFAULT_RADIUS_KM;

  @ApiPropertyOptional({
    description: '1-based page number.',
    default: 1,
    minimum: 1,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({
    description: 'Items per page.',
    default: 20,
    minimum: 1,
    maximum: 50,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number = 20;
}

/**
 * One nearby profile.
 *
 * Deliberately the SAME shape as the Discover feed card ([DiscoverProfileDto])
 * with `distanceKm` filled in, rather than a narrower bespoke object. Two
 * reasons: Flutter's DiscoveryProfileModel.fromJson already parses this exact
 * contract (including `distanceKm`, which existed as `null` before this
 * feature), so Near Me reuses the existing card widgets with no parallel
 * model; and the card needs age/photos/verification badges anyway, so a
 * minimal {id,name,image} would only force a second round trip per profile.
 *
 * What is NOT here is the point: no `latitude`/`longitude`. Another member's
 * coordinates never leave the server. `distanceKm` is rounded to one decimal
 * (see roundDistanceKm) so that repeated queries from different points cannot
 * trilaterate someone's home address.
 */
export interface NearbyProfileDto extends DiscoverProfileDto {
  /** Great-circle distance from the caller, in km, one decimal. Never null
   *  on this endpoint — a row without usable coordinates cannot match. */
  distanceKm: number;
}

/** Envelope for GET /profiles/nearby. */
export interface NearbyProfilesResponseDto {
  success: true;
  profiles: NearbyProfileDto[];
  /** Radius actually applied, in km — echoed so the client can label the
   *  empty state ("No profiles within 100 km") without hardcoding it. */
  radiusKm: number;
  page: number;
  limit: number;
  /** Matches inside the radius after safety filtering, across all pages. */
  total: number;
  hasMore: boolean;
}
