import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import {
  DraftResponse,
  DraftSection,
  ProfileDraftService,
} from '../services/profile-draft.service';
import { ProfileService } from '../services/profile.service';
import { BasicDetailsDto } from '../dto/basic-details.dto';
import { ReligionDetailsDto } from '../dto/religion-details.dto';
import { LanguageDetailsDto } from '../dto/language-details.dto';
import { LocationDetailsDto } from '../dto/location-details.dto';
import { EducationDetailsDto } from '../dto/education-details.dto';
import { PhysicalDetailsDto } from '../dto/physical-details.dto';
import { LifestyleDetailsDto } from '../dto/lifestyle-details.dto';
import { FamilyDetailsDto } from '../dto/family-details.dto';
import { HoroscopeDetailsDto } from '../dto/horoscope-details.dto';
import { PartnerPreferenceDto } from '../dto/partner-preference.dto';

// One PATCH endpoint per wizard step (1-10). Each is a partial save — the
// Flutter wizard calls the matching endpoint on every "Continue" tap, not
// just once at the end. Steps 11 (photos) and 12 (verification) are handled
// by PhotoController and the verification module respectively.
@Controller('profiles/draft')
@UseGuards(FirebaseAuthGuard)
export class ProfileDraftController {
  constructor(
    private readonly draftService: ProfileDraftService,
    private readonly profileService: ProfileService,
  ) {}

  @Get()
  getDraft(@CurrentUser('id') userId: string): Promise<DraftResponse> {
    return this.draftService.getDraft(userId);
  }

  @Patch('basic-details')
  updateBasicDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: BasicDetailsDto,
  ): Promise<DraftResponse> {
    return this.save(userId, 'basicDetails', dto);
  }

  @Patch('religion-details')
  updateReligionDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: ReligionDetailsDto,
  ): Promise<DraftResponse> {
    return this.save(userId, 'religionDetails', dto);
  }

  @Patch('language-details')
  updateLanguageDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: LanguageDetailsDto,
  ): Promise<DraftResponse> {
    return this.save(userId, 'languageDetails', dto);
  }

  @Patch('location-details')
  updateLocationDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: LocationDetailsDto,
  ): Promise<DraftResponse> {
    return this.save(userId, 'locationDetails', dto);
  }

  @Patch('education-details')
  updateEducationDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: EducationDetailsDto,
  ): Promise<DraftResponse> {
    return this.save(userId, 'educationDetails', dto);
  }

  @Patch('physical-details')
  updatePhysicalDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: PhysicalDetailsDto,
  ): Promise<DraftResponse> {
    return this.save(userId, 'physicalDetails', dto);
  }

  @Patch('lifestyle-details')
  updateLifestyleDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: LifestyleDetailsDto,
  ): Promise<DraftResponse> {
    return this.save(userId, 'lifestyleDetails', dto);
  }

  @Patch('family-details')
  updateFamilyDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: FamilyDetailsDto,
  ): Promise<DraftResponse> {
    return this.save(userId, 'familyDetails', dto);
  }

  @Patch('horoscope-details')
  updateHoroscopeDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: HoroscopeDetailsDto,
  ): Promise<DraftResponse> {
    return this.save(userId, 'horoscopeDetails', dto);
  }

  @Patch('partner-preference')
  updatePartnerPreference(
    @CurrentUser('id') userId: string,
    @Body() dto: PartnerPreferenceDto,
  ): Promise<DraftResponse> {
    return this.save(userId, 'partnerPreference', dto);
  }

  /**
   * Persists a wizard section, then — the single reason this controller depends
   * on ProfileService — materialises the user into a real, matchable
   * UserProfile the moment all mandatory fields exist (see
   * ProfileService.syncMatchableFromDraft). That call is non-throwing, so the
   * step save's response is unaffected whether the user is eligible yet or not.
   */
  private async save(
    userId: string,
    section: DraftSection,
    dto: object,
  ): Promise<DraftResponse> {
    const draft = await this.draftService.updateSection(userId, section, dto);
    await this.profileService.syncMatchableFromDraft(userId);
    return draft;
  }
}
