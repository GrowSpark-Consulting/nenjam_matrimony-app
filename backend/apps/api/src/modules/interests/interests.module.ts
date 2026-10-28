import { Module } from '@nestjs/common';
import { StorageModule } from '@app/storage';
import { NotificationsModule } from '../notifications/notifications.module';
import { EntitlementsModule } from '../entitlements/entitlements.module';
import { ProfileFeedMapper } from '../matches/mappers/profile-feed.mapper';
import { InterestsController } from './controllers/interests.controller';
import { InterestsService } from './services/interests.service';
import { InterestsRepository } from './repositories/interests.repository';

/**
 * Interests: send / respond / withdraw / list. InterestsService is exported so
 * MatchesController can own the write endpoint (POST /matches/interest) the
 * frontend targets, without a circular module dependency (MatchesModule imports
 * InterestsModule, never the reverse).
 *
 * ProfileFeedMapper is provided here (its own instance — it's stateless, needs
 * only S3Service) so interest cards reuse the exact Discover card shape;
 * NotificationsModule supplies NotificationsService for the transactional
 * notification writes; EntitlementsModule the monthly interest allowance.
 * PrismaService is global.
 */
@Module({
  imports: [StorageModule, NotificationsModule, EntitlementsModule],
  controllers: [InterestsController],
  providers: [InterestsService, InterestsRepository, ProfileFeedMapper],
  exports: [InterestsService],
})
export class InterestsModule {}
