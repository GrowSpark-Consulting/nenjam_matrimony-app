import { Controller, Get, Post, UseGuards } from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { ProfileService } from '../services/profile.service';
import { ProfileEntity } from '../entities/profile.entity';

// Note: there is deliberately no GET /profiles/:id here. Viewing another
// member's profile (Search/Matches/Discover) is a separate concern with its
// own visibility/privacy rules — this controller only ever resolves "your
// own" profile, from the verified Firebase token.
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
  async finalize(@CurrentUser('id') userId: string): Promise<ProfileEntity> {
    console.log(`[STORY-PERF-SRV] ${Date.now()} finalize() started`);
    const result = await this.profileService.finalize(userId);
    console.log(`[STORY-PERF-SRV] ${Date.now()} finalize() DB work complete`);
    return result;
  }
}
