import { Module } from '@nestjs/common';
import { StorageModule } from '@app/storage';
import { ProfileDraftController } from './controllers/profile-draft.controller';
import { ProfileController } from './controllers/profile.controller';
import { PhotoController } from './controllers/photo.controller';
import { PromptsController } from './controllers/prompts.controller';
import { ProfileDraftService } from './services/profile-draft.service';
import { ProfileService } from './services/profile.service';
import { ProfileCompletionService } from './services/profile-completion.service';
import { PhotoService } from './services/photo.service';
import { PromptsService } from './services/prompts.service';
import { ProfileRepository } from './repositories/profile.repository';
import { PhotoRepository } from './repositories/photo.repository';
import { PromptsRepository } from './repositories/prompts.repository';

@Module({
  imports: [StorageModule],
  controllers: [
    ProfileDraftController,
    ProfileController,
    PhotoController,
    PromptsController,
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
  ],
  exports: [ProfileDraftService, ProfileService],
})
export class ProfilesModule {}
