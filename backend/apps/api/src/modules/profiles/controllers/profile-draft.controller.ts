import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import {
  DraftResponse,
  ProfileDraftService,
} from '../services/profile-draft.service';
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
  constructor(private readonly draftService: ProfileDraftService) {}

  @Get()
  getDraft(@CurrentUser('id') userId: string): Promise<DraftResponse> {
    return this.draftService.getDraft(userId);
  }

  @Patch('basic-details')
  updateBasicDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: BasicDetailsDto,
  ): Promise<DraftResponse> {
    console.log('[PATCH BASIC DETAILS] Controller entered');
    return this.draftService.updateSection(userId, 'basicDetails', dto);
  }

  @Patch('religion-details')
  updateReligionDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: ReligionDetailsDto,
  ): Promise<DraftResponse> {
    return this.draftService.updateSection(userId, 'religionDetails', dto);
  }

  @Patch('language-details')
  updateLanguageDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: LanguageDetailsDto,
  ): Promise<DraftResponse> {
    return this.draftService.updateSection(userId, 'languageDetails', dto);
  }

  @Patch('location-details')
  updateLocationDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: LocationDetailsDto,
  ): Promise<DraftResponse> {
    return this.draftService.updateSection(userId, 'locationDetails', dto);
  }

  @Patch('education-details')
  updateEducationDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: EducationDetailsDto,
  ): Promise<DraftResponse> {
    return this.draftService.updateSection(userId, 'educationDetails', dto);
  }

  @Patch('physical-details')
  updatePhysicalDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: PhysicalDetailsDto,
  ): Promise<DraftResponse> {
    return this.draftService.updateSection(userId, 'physicalDetails', dto);
  }

  @Patch('lifestyle-details')
  updateLifestyleDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: LifestyleDetailsDto,
  ): Promise<DraftResponse> {
    return this.draftService.updateSection(userId, 'lifestyleDetails', dto);
  }

  @Patch('family-details')
  updateFamilyDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: FamilyDetailsDto,
  ): Promise<DraftResponse> {
    return this.draftService.updateSection(userId, 'familyDetails', dto);
  }

  @Patch('horoscope-details')
  updateHoroscopeDetails(
    @CurrentUser('id') userId: string,
    @Body() dto: HoroscopeDetailsDto,
  ): Promise<DraftResponse> {
    return this.draftService.updateSection(userId, 'horoscopeDetails', dto);
  }

  @Patch('partner-preference')
  updatePartnerPreference(
    @CurrentUser('id') userId: string,
    @Body() dto: PartnerPreferenceDto,
  ): Promise<DraftResponse> {
    return this.draftService.updateSection(userId, 'partnerPreference', dto);
  }
}
