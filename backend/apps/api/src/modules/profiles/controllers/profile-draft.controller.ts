import { Body, Controller, Get, Patch, Query, UseGuards } from '@nestjs/common';
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
    @Query('skipMaterialize') skipMaterialize?: string,
  ): Promise<DraftResponse> {
    return this.save(userId, 'basicDetails', dto, skipMaterialize === 'true');
  }

  @Patch('religion-details')
  updateReligionDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: ReligionDetailsDto,
    @Query('skipMaterialize') skipMaterialize?: string,
  ): Promise<DraftResponse> {
    return this.save(
      userId,
      'religionDetails',
      dto,
      skipMaterialize === 'true',
    );
  }

  @Patch('language-details')
  updateLanguageDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: LanguageDetailsDto,
    @Query('skipMaterialize') skipMaterialize?: string,
  ): Promise<DraftResponse> {
    return this.save(
      userId,
      'languageDetails',
      dto,
      skipMaterialize === 'true',
    );
  }

  @Patch('location-details')
  updateLocationDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: LocationDetailsDto,
    @Query('skipMaterialize') skipMaterialize?: string,
  ): Promise<DraftResponse> {
    return this.save(
      userId,
      'locationDetails',
      dto,
      skipMaterialize === 'true',
    );
  }

  @Patch('education-details')
  updateEducationDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: EducationDetailsDto,
    @Query('skipMaterialize') skipMaterialize?: string,
  ): Promise<DraftResponse> {
    return this.save(
      userId,
      'educationDetails',
      dto,
      skipMaterialize === 'true',
    );
  }

  @Patch('physical-details')
  updatePhysicalDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: PhysicalDetailsDto,
    @Query('skipMaterialize') skipMaterialize?: string,
  ): Promise<DraftResponse> {
    return this.save(
      userId,
      'physicalDetails',
      dto,
      skipMaterialize === 'true',
    );
  }

  @Patch('lifestyle-details')
  updateLifestyleDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: LifestyleDetailsDto,
    @Query('skipMaterialize') skipMaterialize?: string,
  ): Promise<DraftResponse> {
    return this.save(
      userId,
      'lifestyleDetails',
      dto,
      skipMaterialize === 'true',
    );
  }

  @Patch('family-details')
  updateFamilyDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: FamilyDetailsDto,
    @Query('skipMaterialize') skipMaterialize?: string,
  ): Promise<DraftResponse> {
    return this.save(userId, 'familyDetails', dto, skipMaterialize === 'true');
  }

  @Patch('horoscope-details')
  updateHoroscopeDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: HoroscopeDetailsDto,
    @Query('skipMaterialize') skipMaterialize?: string,
  ): Promise<DraftResponse> {
    return this.save(
      userId,
      'horoscopeDetails',
      dto,
      skipMaterialize === 'true',
    );
  }

  @Patch('partner-preference')
  updatePartnerPreference(
    @CurrentUser('id') userId: string,
    @Body() dto: PartnerPreferenceDto,
    @Query('skipMaterialize') skipMaterialize?: string,
  ): Promise<DraftResponse> {
    return this.save(
      userId,
      'partnerPreference',
      dto,
      skipMaterialize === 'true',
    );
  }

  /**
   * Persists a wizard section, then — the single reason this controller depends
   * on ProfileService — materialises the user into a real, matchable
   * UserProfile the moment all mandatory fields exist (see
   * ProfileService.syncMatchableFromDraft). A member not yet eligible is a
   * silent no-op; a copy that FAILS fails this request, so a save is never
   * reported as successful while `user_profiles` still holds the old values.
   *
   * [skipMaterialize] — set by the Flutter edit-mode flow (see
   * RegistrationRepository._patchSection), which always calls POST
   * /profiles/finalize immediately after this save. finalize() does its own
   * full writeProfileFromDraft + recalculateAndPersistCompletion pass
   * unconditionally (it has to — it's also called standalone, with no
   * preceding PATCH, from the Profile Review / Registration Completing
   * screens), so materialising here too was pure duplicate work: measured
   * on a physical device, ~1.8s spent doing exactly the same 3 upserts +
   * 4-query completion recompute that finalize() was about to redo
   * unconditionally a moment later. Skipping it here changes nothing about
   * the final DB state — finalize() remains authoritative — it just avoids
   * computing it twice. CREATE mode never sends this flag (it doesn't call
   * finalize per step), so its auto-materialize-on-mandatory-complete
   * behavior is unchanged.
   */
  private async save(
    userId: string,
    section: DraftSection,
    dto: object,
    skipMaterialize: boolean,
  ): Promise<DraftResponse> {
    const draft = await this.draftService.updateSection(userId, section, dto);
    if (!skipMaterialize) {
      await this.profileService.syncMatchableFromDraft(
        userId,
        draft.data as Record<string, Record<string, unknown>>,
      );
    }
    return draft;
  }
}
