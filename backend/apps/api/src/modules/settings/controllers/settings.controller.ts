import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Patch,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { AccountDeletionService } from '../services/account-deletion.service';
import { SettingsService } from '../services/settings.service';
import { PrivacySettings } from '../repositories/settings.repository';
import { UpdatePrivacyDto } from '../dto/update-privacy.dto';

// Every route derives the user from the verified Firebase token
// (`@CurrentUser('id')`), so a caller can only ever read or change their own
// settings. Business logic lives in the services — this controller only maps
// HTTP to a service call.
@Controller('settings')
@UseGuards(FirebaseAuthGuard)
export class SettingsController {
  constructor(
    private readonly settingsService: SettingsService,
    private readonly accountDeletionService: AccountDeletionService,
  ) {}

  /** GET /settings — the caller's settings (privacy preferences today). */
  @Get()
  getSettings(@CurrentUser('id') userId: string): Promise<PrivacySettings> {
    return this.settingsService.getPrivacySettings(userId);
  }

  /** PATCH /settings/privacy — partial update of the caller's privacy
   *  preferences; omitted fields are left unchanged. */
  @Patch('privacy')
  updatePrivacy(
    @CurrentUser('id') userId: string,
    @Body() dto: UpdatePrivacyDto,
  ): Promise<PrivacySettings> {
    return this.settingsService.updatePrivacySettings(userId, dto);
  }

  /**
   * DELETE /settings/delete-account — permanently and irreversibly deletes the
   * authenticated user's account: all database rows, all uploaded storage
   * objects, and the Firebase auth identity. Matches the frontend contract
   * (settings_repository_impl.dart -> ApiEndpoints.deleteAccount).
   */
  @Delete('delete-account')
  @HttpCode(HttpStatus.NO_CONTENT)
  deleteAccount(@CurrentUser('id') userId: string): Promise<void> {
    return this.accountDeletionService.deleteAccount(userId);
  }
}
