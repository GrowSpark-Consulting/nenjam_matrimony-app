import { Module } from '@nestjs/common';
import { StorageModule } from '@app/storage';
import { ProfileDraftController } from './controllers/profile-draft.controller';
import { ProfileController } from './controllers/profile.controller';
import { PhotoController } from './controllers/photo.controller';
import { PromptsController } from './controllers/prompts.controller';
import { ProfileCompletionController } from './controllers/profile-completion.controller';
import { ProfileDraftService } from './services/profile-draft.service';
import { ProfileService } from './services/profile.service';
import { ProfileCompletionService } from './services/profile-completion.service';
import { PhotoService } from './services/photo.service';
import { PromptsService } from './services/prompts.service';
import { ProfileRepository } from './repositories/profile.repository';
import { PhotoRepository } from './repositories/photo.repository';
import { PromptsRepository } from './repositories/prompts.repository';
import { RecommendationDismissalRepository } from './repositories/recommendation-dismissal.repository';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  imports: [StorageModule, NotificationsModule],
  controllers: [
    ProfileDraftController,
    ProfileController,
    PhotoController,
    PromptsController,
    ProfileCompletionController,
  ],
  providers: [
    ProfileDraftService,
    ProfileService,
    ProfileCompletionService,
    PhotoService,
    PromptsService,
    ProfileRepository,
    PhotoRepository,
    PromptsRepository,
    RecommendationDismissalRepository,
  ],
  exports: [ProfileDraftService, ProfileService],
})
export class ProfilesModule {}
