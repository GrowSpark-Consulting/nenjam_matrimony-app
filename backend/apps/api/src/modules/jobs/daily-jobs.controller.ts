import {
  Controller,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiExcludeController } from '@nestjs/swagger';
import { createHash, timingSafeEqual } from 'node:crypto';
import { AppConfigService } from '@app/config';
import { DailyJobsService, type DailyRunReport } from './daily-jobs.service';

/** Same length whatever was sent, so the comparison never leaks it. */
const digest = (value: string) => createHash('sha256').update(value).digest();

/**
 * `POST /internal/jobs/daily` — called once a day by the GitHub Actions
 * schedule (.github/workflows/daily-jobs.yml), never by a person or the
 * apps. No Firebase token: the caller proves itself with the X-Jobs-Secret
 * header (JOBS_SECRET). Answers 200 with a report; `ok: false` means a job
 * failed (the workflow fails the run so someone sees it).
 */
@ApiExcludeController()
@Controller('internal/jobs')
export class DailyJobsController {
  constructor(
    private readonly jobs: DailyJobsService,
    private readonly config: AppConfigService,
  ) {}

  @Post('daily')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  daily(
    @Headers('x-jobs-secret') secret: string | undefined,
  ): Promise<DailyRunReport> {
    this.authorize(secret);
    return this.jobs.runAll();
  }

  private authorize(secret: string | undefined): void {
    const expected = this.config.jobs?.secret;
    if (!expected) {
      throw new ServiceUnavailableException({
        statusCode: 503,
        error: 'Service Unavailable',
        code: 'JOBS_UNAVAILABLE',
        message: 'Daily jobs are not configured.',
      });
    }
    if (
      typeof secret !== 'string' ||
      !timingSafeEqual(digest(secret), digest(expected))
    ) {
      throw new UnauthorizedException({
        statusCode: 401,
        error: 'Unauthorized',
        code: 'JOBS_SECRET_INVALID',
        message: 'Missing or wrong X-Jobs-Secret.',
      });
    }
  }
}
