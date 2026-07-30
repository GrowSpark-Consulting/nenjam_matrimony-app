import { Module } from '@nestjs/common';
import { StorageModule } from '@app/storage';
import { SettingsController } from './controllers/settings.controller';
import { AccountDeletionService } from './services/account-deletion.service';
import { SettingsService } from './services/settings.service';
import { SettingsRepository } from './repositories/settings.repository';

// PrismaService (@app/database) and FirebaseService (@app/firebase) are provided
// by their @Global modules; only StorageModule (S3Service) needs importing.
@Module({
  imports: [StorageModule],
  controllers: [SettingsController],
  providers: [SettingsService, SettingsRepository, AccountDeletionService],
})
export class SettingsModule {}
