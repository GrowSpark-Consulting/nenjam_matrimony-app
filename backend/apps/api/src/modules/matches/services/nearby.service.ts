import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import type { Gender } from '../../../../../../libs/database/generated/client';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import { NearbyRepository } from '../repositories/nearby.repository';
import {
  DEFAULT_RADIUS_KM,
  MAX_RADIUS_KM,
  type NearbyProfileDto,
  type NearbyProfilesResponseDto,
  type NearbyQueryDto,
} from '../dto/nearby.dto';
import {
  isValidCoordinate,
  roundDistanceKm,
  type GeoPoint,
} from '../geo/haversine';

/**
 * "Near Me" — profiles within a radius of the caller, nearest first.
 *
 * Reads only. Storing the caller's own coordinates is a separate, explicit
 * write (PUT /profiles/me/location) rather than a side effect of this GET:
 * a GET that quietly persists whatever location it is handed would record a
 * position every time a screen refreshes, and would let a replayed URL
 * rewrite a member's stored location.
 */
@Injectable()
export class NearbyService {
  private readonly logger = new Logger(NearbyService.name);

  constructor(
    private readonly repository: NearbyRepository,
    private readonly mapper: ProfileFeedMapper,
  ) {}

  async findNearby(
    userId: string,
    query: NearbyQueryDto,
  ): Promise<NearbyProfilesResponseDto> {
    const radiusKm = Math.min(
      query.radiusKm ?? DEFAULT_RADIUS_KM,
      MAX_RADIUS_KM,
    );
    const page = query.page ?? 1;
    const limit = query.limit ?? 20;

    const self = await this.repository.findSelf(userId);

    // No finalized profile means the caller's gender is unknown, and
    // "opposite gender" is a mandatory rule for every feed in this app. Fail
    // closed with an empty page, exactly as buildFeedWhere does, rather than
    // returning an unfiltered mixed-gender list.
    if (!self) {
      return this.emptyResult(radiusKm, page, limit);
    }

    const centre = this.resolveCentre(query, self);
    const oppositeGender: Gender = self.gender === 'MALE' ? 'FEMALE' : 'MALE';

    const candidates = await this.repository.findCandidatesWithin(
      centre,
      radiusKm,
      oppositeGender,
      userId,
    );
    if (candidates.length === 0) {
      return this.emptyResult(radiusKm, page, limit);
    }

    // Second phase: the same block / declined-interest / account-status rules
    // the Discover feed applies. Some candidates disappear here.
    const rows = await this.repository.findVisibleProfiles(
      candidates.map((c) => c.userId),
      userId,
    );

    const distanceByUserId = new Map(
      candidates.map((c) => [c.userId, c.distanceKm]),
    );

    const ordered = rows
      .map((row) => ({
        row,
        distanceKm: distanceByUserId.get(String(row.userId)),
      }))
      .filter(
        (entry): entry is { row: (typeof rows)[number]; distanceKm: number } =>
          entry.distanceKm !== undefined,
      )
      // Nearest first. User id breaks ties so two profiles at an identical
      // distance keep a stable order between requests — otherwise one can show
      // up on both page 1 and page 2 while another is skipped entirely.
      .sort(
        (a, b) =>
          a.distanceKm - b.distanceKm ||
          String(a.row.userId).localeCompare(String(b.row.userId)),
      );

    const total = ordered.length;
    const start = (page - 1) * limit;
    const pageEntries = ordered.slice(start, start + limit);

    // Map only the current page: ProfileFeedMapper presigns every photo URL
    // against S3, so mapping all candidates would issue hundreds of signing
    // calls to render twenty cards.
    const dtos = await this.mapper.toDtoList(pageEntries.map((e) => e.row));

    const profiles: NearbyProfileDto[] = dtos.map((dto, index) => ({
      ...dto,
      distanceKm: roundDistanceKm(pageEntries[index].distanceKm),
    }));

    return {
      success: true,
      profiles,
      radiusKm,
      page,
      limit,
      total,
      hasMore: start + pageEntries.length < total,
    };
  }

  /**
   * Where to search from: the coordinates on this request if it carries a
   * valid pair, otherwise the caller's last stored location.
   *
   * Latitude and longitude must arrive together — half a coordinate is a
   * client bug, and silently falling back to a stored location for the other
   * half would search from a point the caller never asked for.
   */
  private resolveCentre(
    query: NearbyQueryDto,
    self: {
      latitude: number | null;
      longitude: number | null;
    },
  ): GeoPoint {
    const hasQueryLat = query.latitude !== undefined;
    const hasQueryLon = query.longitude !== undefined;

    if (hasQueryLat !== hasQueryLon) {
      throw new BadRequestException(
        'latitude and longitude must be provided together.',
      );
    }

    if (hasQueryLat && hasQueryLon) {
      // Already range-checked by the DTO validators; re-checked here because
      // this is the last point before the values reach a SQL expression.
      if (!isValidCoordinate(query.latitude, query.longitude)) {
        throw new BadRequestException('Invalid latitude/longitude.');
      }
      return { latitude: query.latitude, longitude: query.longitude! };
    }

    if (!isValidCoordinate(self.latitude, self.longitude)) {
      throw new BadRequestException(
        'No location available. Send latitude and longitude, or store one with PUT /profiles/me/location.',
      );
    }

    return { latitude: self.latitude, longitude: self.longitude! };
  }

  private emptyResult(
    radiusKm: number,
    page: number,
    limit: number,
  ): NearbyProfilesResponseDto {
    return {
      success: true,
      profiles: [],
      radiusKm,
      page,
      limit,
      total: 0,
      hasMore: false,
    };
  }
}
