import { Injectable, Logger } from '@nestjs/common';
import { PsychologyRepository } from '../repositories/psychology.repository';
import { unsupportedQuizReason } from './psychology-data.guards';
import { errorMessage, warnThrottled } from './psychology-log';
import type { ScoringQuiz } from './psychology-compatibility.types';

/** How long a loaded quiz is reused. The active quiz changes on a content
 *  release, not per request, so this trades ≤1 minute of staleness for
 *  removing two database round trips from every Discover request. */
const FOUND_TTL_MS = 60_000;
/** "No usable quiz" is cached too — briefly — so an unseeded environment
 *  doesn't pay a query per request to learn the same thing. Short, so seeding
 *  the quiz takes effect quickly. */
const ABSENT_TTL_MS = 15_000;
/** If a refresh fails, the previous quiz keeps being served for this long. */
const MAX_STALE_MS = 10 * 60_000;

interface CacheEntry {
  value: ScoringQuiz | null;
  loadedAt: number;
  ttlMs: number;
}

/**
 * The active quiz's scoring questions, cached in-process.
 *
 * Returns null when there is no active quiz OR the active quiz can't be scored
 * against the approved matrix (see unsupportedQuizReason) — in both cases
 * psychology simply isn't applicable, and the caller carries on without it.
 *
 * Throws only when the database read fails and there is no usable previous
 * value. Callers on a request path that must not fail (Discover) catch that.
 *
 * Staleness: the cache is per API instance and expires by time only. A content
 * release therefore reaches every instance within FOUND_TTL_MS. Question
 * content is immutable per question id by convention (see the seeder), which is
 * what makes a short-lived cache safe.
 */
@Injectable()
export class PsychologyScoringQuizProvider {
  private readonly logger = new Logger(PsychologyScoringQuizProvider.name);
  private entry: CacheEntry | null = null;
  private inFlight: Promise<ScoringQuiz | null> | null = null;

  constructor(private readonly repository: PsychologyRepository) {}

  async get(now: number = Date.now()): Promise<ScoringQuiz | null> {
    if (this.entry && now - this.entry.loadedAt < this.entry.ttlMs) {
      return this.entry.value;
    }

    // Concurrent requests share one refresh instead of each hitting the DB.
    if (!this.inFlight) {
      this.inFlight = this.load().finally(() => {
        this.inFlight = null;
      });
    }

    try {
      return await this.inFlight;
    } catch (error) {
      if (this.entry && now - this.entry.loadedAt < MAX_STALE_MS) {
        warnThrottled(
          this.logger,
          'quiz-refresh-failed',
          `Serving the previously loaded psychology quiz: refresh failed (${errorMessage(error)})`,
        );
        return this.entry.value;
      }
      throw error;
    }
  }

  /** Test seam / manual flush. */
  invalidate(): void {
    this.entry = null;
  }

  private async load(): Promise<ScoringQuiz | null> {
    const quiz = await this.repository.findActiveQuiz();
    if (!quiz) {
      warnThrottled(
        this.logger,
        'no-active-quiz',
        'No active psychology quiz is configured, so psychology is not applied to Discover. Seed it with "pnpm seed:quiz".',
      );
      this.entry = { value: null, loadedAt: Date.now(), ttlMs: ABSENT_TTL_MS };
      return null;
    }

    const questions = await this.repository.findScoringQuestions(quiz.id);
    const unsupported = unsupportedQuizReason(questions);
    if (unsupported !== null) {
      warnThrottled(
        this.logger,
        'quiz-unsupported',
        `Psychology scoring disabled: active quiz "${quiz.id}" cannot be scored — ${unsupported}.`,
      );
      this.entry = { value: null, loadedAt: Date.now(), ttlMs: ABSENT_TTL_MS };
      return null;
    }

    const value: ScoringQuiz = {
      quizId: quiz.id,
      version: quiz.version,
      questions,
    };
    this.entry = { value, loadedAt: Date.now(), ttlMs: FOUND_TTL_MS };
    return value;
  }
}
