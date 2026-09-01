import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { READ_LIMIT } from '../../../throttling';
import { NearbyService } from '../services/nearby.service';
import type { NearbyProfilesResponseDto } from '../dto/nearby.dto';
import { NearbyQueryDto } from '../dto/nearby.dto';

/**
 * Proximity search — GET /profiles/nearby.
 *
 * Mounted under `profiles` to match the client-facing path, but lives in the
 * matches module because that is where every "profiles other than mine" read
 * already lives: the feed mapper, the safety-exclusion builder and the shared
 * card DTO. The profiles module is deliberately scoped to "your own profile"
 * only (see ProfileController's header note), and this endpoint is the
 * opposite of that.
 *
 * Nest allows the shared `profiles` prefix because no route collides:
 * ProfileController owns `me` and `finalize`, the draft/prompt/photo
 * controllers own their own sub-paths, and none of them registers a
 * `:id`-style wildcard that `nearby` could be swallowed by.
 */
@ApiTags('Discover')
@ApiBearerAuth('firebase')
@Controller('profiles')
@UseGuards(FirebaseAuthGuard)
export class NearbyController {
  constructor(private readonly nearbyService: NearbyService) {}

  /**
   * Rate limited at the read tier, like the feed: this returns other members'
   * profile data a page at a time, and adding a coordinate parameter makes it
   * the one endpoint that could be walked in a grid to map the userbase
   * geographically. The distances it returns are rounded to 100m for the same
   * reason — see roundDistanceKm.
   */
  @Throttle(READ_LIMIT)
  @Get('nearby')
  @ApiOperation({
    summary: 'Profiles within a radius of the caller, nearest first.',
    description:
      "Returns display-safe cards with a calculated `distanceKm`. Other members' raw coordinates are never returned. Omit latitude/longitude to search from the location last stored via PUT /profiles/me/location.",
  })
  @ApiOkResponse({
    description: 'Nearby profiles, sorted by ascending distance.',
  })
  findNearby(
    @CurrentUser('id') userId: string,
    @Query() query: NearbyQueryDto,
  ): Promise<NearbyProfilesResponseDto> {
    return this.nearbyService.findNearby(userId, query);
  }
}
