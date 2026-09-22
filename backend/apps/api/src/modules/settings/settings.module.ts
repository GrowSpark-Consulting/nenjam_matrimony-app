import { Module } from '@nestjs/common';
import { StorageModule } from '@app/storage';
import { SettingsController } from './controllers/settings.controller';
import { AccountDeletionService } from './services/account-deletion.service';
import { SettingsService } from './services/settings.service';
import { SettingsRepository } from './repositories/settings.repository';
import { EntitlementsModule } from '../entitlements/entitlements.module';

// PrismaService (@app/database) and FirebaseService (@app/firebase) are provided
// by their @Global modules; StorageModule (S3Service) and EntitlementsModule
// (premium gating for the privacy settings) need importing.
@Module({
  imports: [StorageModule, EntitlementsModule],
  controllers: [SettingsController],
  providers: [SettingsService, SettingsRepository, AccountDeletionService],
})
export class SettingsModule {}
