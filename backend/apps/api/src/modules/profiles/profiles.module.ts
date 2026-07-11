import { Module } from '@nestjs/common';
import { ProfileDraftController } from './controllers/profile-draft.controller';
import { ProfileController } from './controllers/profile.controller';
import { PhotoController } from './controllers/photo.controller';
import { ProfileDraftService } from './services/profile-draft.service';
import { ProfileService } from './services/profile.service';
import { PhotoService } from './services/photo.service';
import { ProfileRepository } from './repositories/profile.repository';
import { PhotoRepository } from './repositories/photo.repository';

@Module({
  controllers: [ProfileDraftController, ProfileController, PhotoController],
  providers: [
    ProfileDraftService,
    ProfileService,
    PhotoService,
    ProfileRepository,
    PhotoRepository,
  ],
  exports: [ProfileDraftService, ProfileService],
})
export class ProfilesModule {}
