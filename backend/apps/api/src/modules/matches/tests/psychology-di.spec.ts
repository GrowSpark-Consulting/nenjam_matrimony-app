import { Global, Module } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { AppConfigModule, AppConfigService } from '@app/config';
import { FirebaseAuthGuard } from '@app/common';
import { PrismaService } from '@app/database';
import { FeedInvalidationService } from '../cache/feed-invalidation.service';
import { PsychologyModule } from '../../psychology/psychology.module';
import { PsychologyService } from '../../psychology/services/psychology.service';
import { PsychologyScoringQuizProvider } from '../../psychology/scoring/psychology-scoring-quiz.provider';
import { PsychologyMatchContextService } from '../scoring/psychology/psychology-match-context.service';

/**
 * Unit specs build services by hand with mocks, so they can not see a missing
 * provider or export. This compiles the REAL PsychologyModule (plus the real
 * PsychologyMatchContextService, which MatchesModule provides) with only the
 * globally-provided infrastructure stubbed — the same resolution the running
 * app performs.
 */
const STUB_CONFIG = {
  psychology: { enabled: true, timeoutMs: 800, retakeCooldownDays: 7 },
  jwt: { secret: 'a-test-secret-of-sufficient-length' },
};

@Global()
@Module({
  providers: [
    { provide: PrismaService, useValue: {} },
    { provide: FeedInvalidationService, useValue: { invalidate: jest.fn() } },
  ],
  exports: [PrismaService, FeedInvalidationService],
})
class StubGlobalsModule {}

// Stands in for the real AppConfigModule (which loads and validates the whole
// environment) with the same export.
@Module({
  providers: [{ provide: AppConfigService, useValue: STUB_CONFIG }],
  exports: [AppConfigService],
})
class StubConfigModule {}

describe('Psychology dependency-injection graph', () => {
  it('resolves PsychologyService, and exports what MatchesModule needs', async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [StubGlobalsModule, StubConfigModule, PsychologyModule],
      providers: [PsychologyMatchContextService],
    })
      .overrideModule(AppConfigModule)
      .useModule(StubConfigModule)
      .overrideGuard(FirebaseAuthGuard)
      .useValue({ canActivate: () => true })
      .compile();

    expect(moduleRef.get(PsychologyService)).toBeInstanceOf(PsychologyService);
    expect(moduleRef.get(PsychologyScoringQuizProvider)).toBeInstanceOf(
      PsychologyScoringQuizProvider,
    );
    expect(moduleRef.get(PsychologyMatchContextService)).toBeInstanceOf(
      PsychologyMatchContextService,
    );
  });
});
