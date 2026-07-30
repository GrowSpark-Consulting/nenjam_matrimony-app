import { Module } from '@nestjs/common';
import { StorageModule } from '@app/storage';
import { BlocksController } from './controllers/blocks.controller';
import { BlocksService } from './services/blocks.service';
import { BlocksRepository } from './repositories/blocks.repository';
import { ProfileFeedMapper } from '../matches/mappers/profile-feed.mapper';

/**
 * Blocks: block / unblock a member by user id, and list the caller's blocked
 * members. PrismaService is global; StorageModule is imported for
 * ProfileFeedMapper's photo presigning (own instance here, same as
 * Interests/Shortlist/Chat — it's stateless, needing only S3Service — so
 * blocked-member cards render identically to Discover cards).
 *
 * BlocksService is exported in case another module ever needs to trigger a
 * block programmatically; the read-side block check other modules use today
 * (`isBlockedBetween`) stays where it already lives in each of their own
 * repositories (interests/shortlist/chat) — see
 * `filters/block-exclusion.builder.ts` for the shared list-filtering fragment.
 */
@Module({
  imports: [StorageModule],
  controllers: [BlocksController],
  providers: [BlocksService, BlocksRepository, ProfileFeedMapper],
  exports: [BlocksService],
})
export class BlocksModule {}
