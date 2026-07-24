import { Module } from '@nestjs/common';
import { StorageModule } from '@app/storage';
import { SettingsController } from './controllers/settings.controller';
import { AccountDeletionService } from './services/account-deletion.service';

// PrismaService (@app/database) and FirebaseService (@app/firebase) are provided
// by their @Global modules; only StorageModule (S3Service) needs importing.
@Module({
  imports: [StorageModule],
  controllers: [SettingsController],
  providers: [AccountDeletionService],
})
export class SettingsModule {}
