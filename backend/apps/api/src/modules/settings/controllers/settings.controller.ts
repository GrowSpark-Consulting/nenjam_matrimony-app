import {
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { AccountDeletionService } from '../services/account-deletion.service';

@Controller('settings')
@UseGuards(FirebaseAuthGuard)
export class SettingsController {
  constructor(
    private readonly accountDeletionService: AccountDeletionService,
  ) {}

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
