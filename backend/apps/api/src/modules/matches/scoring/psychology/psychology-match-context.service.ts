import { Injectable, Logger } from '@nestjs/common';
import { AppConfigService } from '@app/config';
import { PsychologyRepository } from '../../../psychology/repositories/psychology.repository';
import { PsychologyScoringQuizProvider } from '../../../psychology/scoring/psychology-scoring-quiz.provider';
import {
  coversQuestions,
  parseStoredAnswers,
  responseMatchesQuizVersion,
} from '../../../psychology/scoring/psychology-data.guards';
import {
  errorMessage,
  warnThrottled,
} from '../../../psychology/scoring/psychology-log';
import type {
  ScoringQuestion,
  ScoringQuiz,
} from '../../../psychology/scoring/psychology-compatibility.types';
import {
  PsychologyCircuitBreaker,
  PsychologyTimeoutError,
  withTimeout,
} from './psychology-fail-open';

export interface PsychologyMatchContext {
  /** Empty when psychology can't apply to this request for any reason — it is
   *  disabled, there's no usable quiz, the seeker hasn't completed it, or a
   *  lookup failed. Scoring then proceeds without the psychology signal. */
  questions: ScoringQuestion[];
  answersByUserId: ReadonlyMap<string, Record<string, string>>;
}

/** The seeker's answers plus the quiz they answered; null = psychology can't
 *  apply to this seeker on this request. */
export interface SeekerPsychology {
  quiz: ScoringQuiz;
  answers: Record<string, string>;
}
export type SeekerLookup = Promise<SeekerPsychology | null>;

const EMPTY_CONTEXT: PsychologyMatchContext = {
  questions: [],
  answersByUserId: new Map(),
};

/**
 * Everything one Discover request needs to let PSYCHOLOGY_COMPATIBILITY_SIGNAL
 * do its work: the active quiz's scoring questions, the seeker's answers, and
 * the answers of whichever candidates have completed the quiz.
 *
 * ── The contract: this service never throws and never blocks unboundedly ──
 *
 * Psychology is an optional signal, so no failure in here may reach the
 * member. Every public method resolves — with `null` / an empty context — on
 * any of: the feature being switched off, a database error, a query that
 * outruns its time budget, an open circuit breaker, a missing or unscoreable
 * quiz, or stored answers that are malformed or out of date. Discover then
 * ranks with the same non-psychology signals it always had.
 *
 * ── Cost ──
 *
 * The quiz and its questions come from an in-process cache
 * (PsychologyScoringQuizProvider), so a typical request issues at most two
 * queries: the seeker's own row — which FeedService starts concurrently with
 * the candidate query, so for the majority who haven't taken the quiz it adds
 * no latency at all — and, only when the seeker has answered, one batch read
 * for the candidate pool. There is never a query per candidate.
 */
@Injectable()
export class PsychologyMatchContextService {
  private readonly logger = new Logger(PsychologyMatchContextService.name);
  private readonly breaker = new PsychologyCircuitBreaker();

  /**
   * Cumulative, per API instance. There is no metrics backend to push these
   * to yet; they exist so a health probe or a metrics exporter can read them
   * without changing this class, and so tests can assert on outcomes.
   */
  readonly stats = { failures: 0, timeouts: 0, breakerSkips: 0 };

  constructor(
    private readonly repository: PsychologyRepository,
    private readonly quizProvider: PsychologyScoringQuizProvider,
    private readonly config: AppConfigService,
  ) {}

  /**
   * Starts the seeker-side lookup. Call it before awaiting the candidate query
   * so the two run concurrently. The returned promise never rejects, so it is
   * safe to abandon (e.g. if the candidate query itself throws).
   */
  prefetchSeeker(seekerId: string): SeekerLookup {
    return this.guarded('seeker lookup', async () => {
      const quiz = await this.quizProvider.get();
      if (!quiz) return null;

      const row = await this.repository.findUserAnswers(seekerId, quiz.quizId);
      const answers =
        row && responseMatchesQuizVersion(row.quizVersion, quiz.version)
          ? parseStoredAnswers(row.answers)
          : null;
      // No response, malformed answers, or a response that predates the
      // quiz's current content: in every case the seeker has no usable
      // psychology profile, so no candidate's answers could matter either.
      if (!answers || !coversQuestions(answers, quiz.questions)) return null;

      return { quiz, answers };
    });
  }

  async loadContext(
    seekerId: string,
    candidateIds: string[],
    seeker: SeekerLookup = this.prefetchSeeker(seekerId),
  ): Promise<PsychologyMatchContext> {
    // Defensive: a caller-supplied lookup is expected never to reject, but
    // this method's contract is that it never throws.
    const seekerPsychology = await seeker.catch(() => null);
    if (!seekerPsychology) return EMPTY_CONTEXT;

    const { quiz, answers } = seekerPsychology;
    const candidateRows = await this.guarded('candidate lookup', () =>
      this.repository.findResponsesForUsers(candidateIds, quiz.quizId),
    );
    if (!candidateRows) return EMPTY_CONTEXT;

    const answersByUserId = new Map<string, Record<string, string>>();
    answersByUserId.set(seekerId, answers);
    for (const row of candidateRows) {
      if (!responseMatchesQuizVersion(row.quizVersion, quiz.version)) continue;
      const parsed = parseStoredAnswers(row.answers);
      // A candidate whose stored answers don't cover the quiz as it is now is
      // left out, which reads as "hasn't completed it" — never as a
      // partial-quiz score.
      if (parsed && coversQuestions(parsed, quiz.questions)) {
        answersByUserId.set(row.userId, parsed);
      }
    }

    return { questions: quiz.questions, answersByUserId };
  }

  /**
   * Runs one psychology lookup under the feature switch, the circuit breaker
   * and the time budget. Resolves null — never rejects — when it can't
   * produce a value.
   */
  private async guarded<T>(
    label: string,
    operation: () => Promise<T>,
  ): Promise<T | null> {
    try {
      const { enabled, timeoutMs } = this.config.psychology;
      if (!enabled) return null;

      if (!this.breaker.allow()) {
        this.stats.breakerSkips += 1;
        warnThrottled(
          this.logger,
          'breaker-open',
          'Psychology lookups are paused after repeated failures; Discover is ranking without them.',
        );
        return null;
      }

      const result = await withTimeout(operation(), timeoutMs);
      this.breaker.recordSuccess();
      return result;
    } catch (error) {
      this.breaker.recordFailure();
      if (error instanceof PsychologyTimeoutError) this.stats.timeouts += 1;
      else this.stats.failures += 1;
      warnThrottled(
        this.logger,
        `failed:${label}`,
        `Psychology ${label} failed; Discover continues without psychology: ${errorMessage(error)}`,
      );
      return null;
    }
  }
}
