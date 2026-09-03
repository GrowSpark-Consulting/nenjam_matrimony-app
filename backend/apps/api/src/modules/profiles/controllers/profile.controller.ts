import { Body, Controller, Get, Post, Put, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { WRITE_LIMIT } from '../../../throttling';
import { ProfileService } from '../services/profile.service';
import { ProfileEntity } from '../entities/profile.entity';
import {
  UpdateLocationDto,
  type LocationResponseDto,
} from '../dto/update-location.dto';

// Note: there is deliberately no GET /profiles/:id here. Viewing another
// member's profile (Search/Matches/Discover) is a separate concern with its
// own visibility/privacy rules — this controller only ever resolves "your
// own" profile, from the verified Firebase token.
//
// GET /profiles/nearby is the same kind of separate concern and lives in the
// matches module (NearbyController), which owns every "other members'
// profiles" read along with the safety filters those require.
@Controller('profiles')
@UseGuards(FirebaseAuthGuard)
export class ProfileController {
  constructor(private readonly profileService: ProfileService) {}

  @Get('me')
  getOwn(@CurrentUser('id') userId: string): Promise<ProfileEntity> {
    return this.profileService.getOwn(userId);
  }

  // Called from the Profile Review screen's "Enter App" button — maps the
  // accumulated draft (see ProfileDraftService) into UserProfile /
  // AstrologyProfile / PartnerPreference. Idempotent: re-finalizing updates
  // the existing row rather than creating a duplicate.
  @Post('finalize')
  finalize(@CurrentUser('id') userId: string): Promise<ProfileEntity> {
    return this.profileService.finalize(userId);
  }

  /**
   * Stores the caller's device coordinates after they grant OS location
   * permission, making them discoverable in other members' Near Me results.
   *
   * PUT rather than POST: one location per member, replaced wholesale, so
   * repeating the same call is idempotent — which matters because the client
   * calls it on every Near Me open.
   *
   * Rate limited at the write tier. This is a state-changing call that a
   * background location stream could otherwise fire continuously, and the
   * limit also bounds how fast a compromised token could rewrite a member's
   * stored position.
   */
  @Throttle(WRITE_LIMIT)
  @Put('me/location')
  updateLocation(
    @CurrentUser('id') userId: string,
    @Body() dto: UpdateLocationDto,
  ): Promise<LocationResponseDto> {
    return this.profileService.updateLocation(
      userId,
      dto.latitude,
      dto.longitude,
      dto.accuracyM,
    );
  }
}
