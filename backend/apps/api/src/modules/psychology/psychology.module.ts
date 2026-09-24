import { Module } from '@nestjs/common';
import { PsychologyController } from './controllers/psychology.controller';
import { PsychologyService } from './services/psychology.service';
import { PsychologyRepository } from './repositories/psychology.repository';
import { PsychologyCompatibilityService } from './scoring/psychology-compatibility.service';

// Marriage Compatibility Quiz — answer storage + validation, plus the
// standalone pairwise compatibility engine (PsychologyCompatibilityService).
// PrismaService is global, so no DatabaseModule import is needed here.
// Deliberately does not import MatchesModule/CompatibilityService.
// PsychologyRepository is exported so MatchesModule can read quiz/response
// data for live Discover scoring (matches/scoring/psychology/
// psychology-match-context.service.ts) — the only cross-module dependency
// this feature has, and it runs one direction only (matches depends on
// psychology's repository; psychology never depends on matches).
@Module({
  controllers: [PsychologyController],
  providers: [
    PsychologyService,
    PsychologyRepository,
    PsychologyCompatibilityService,
  ],
  exports: [PsychologyRepository],
})
export class PsychologyModule {}
