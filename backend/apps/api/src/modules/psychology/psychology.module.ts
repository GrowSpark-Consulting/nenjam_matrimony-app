import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { PsychologyController } from './controllers/psychology.controller';
import { PsychologyService } from './services/psychology.service';
import { PsychologyRepository } from './repositories/psychology.repository';
import { PsychologyScoringQuizProvider } from './scoring/psychology-scoring-quiz.provider';

// Marriage Compatibility Quiz — answer storage + validation, and the scoring
// data Discover reads. PrismaService and FeedInvalidationService are global,
// so no DatabaseModule / FeedCacheModule import is needed here.
// Deliberately does not import MatchesModule/CompatibilityService.
// PsychologyRepository and PsychologyScoringQuizProvider are exported so
// MatchesModule can read quiz/response data for live Discover scoring
// (matches/scoring/psychology/psychology-match-context.service.ts) — the only
// cross-module dependency this feature has, and it runs one direction only
// (matches depends on psychology; psychology never depends on matches).
@Module({
  imports: [AppConfigModule],
  controllers: [PsychologyController],
  providers: [
    PsychologyService,
    PsychologyRepository,
    PsychologyScoringQuizProvider,
  ],
  exports: [PsychologyRepository, PsychologyScoringQuizProvider],
})
export class PsychologyModule {}
