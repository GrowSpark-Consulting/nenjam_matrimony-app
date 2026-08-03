import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '@app/database';
// Deep relative path, matching every other repository in the codebase — the
// generated client sits outside libs/database/src, so the "@app/database/*"
// alias (which maps to libs/database/src/*) cannot reach it.
import { EmailStatus, type Prisma } from '../../../database/generated/client';

export interface CreateEmailLogInput {
  userId?: string;
  recipient: string;
  subject: string;
  template: string;
  provider: string;
  metadata?: Prisma.InputJsonValue;
}

export interface MarkSentInput {
  id: string;
  provider: string;
  providerMessageId: string;
  attempts: number;
  metadata?: Prisma.InputJsonValue;
}

export interface MarkFailedInput {
  id: string;
  error: string;
  attempts: number;
  /** DEAD_LETTER once BullMQ has exhausted retries; FAILED while more remain. */
  terminal: boolean;
  metadata?: Prisma.InputJsonValue;
}

/**
 * Persistence for email delivery records.
 *
 * Every method here is best-effort by design: a logging failure must never
 * fail the send or crash the worker. A dropped audit row is a much smaller
 * problem than an OTP that never arrives because the log write timed out.
 */
@Injectable()
export class EmailLogRepository {
  private readonly logger = new Logger(EmailLogRepository.name);

  constructor(private readonly prisma: PrismaService) {}

  /** Returns the new row's id, or undefined if the write failed. Callers
   *  treat undefined as "carry on without a log row". */
  async create(input: CreateEmailLogInput): Promise<string | undefined> {
    try {
      const row = await this.prisma.emailLog.create({
        data: {
          userId: input.userId ?? null,
          recipient: input.recipient,
          subject: input.subject,
          template: input.template,
          provider: input.provider,
          status: EmailStatus.QUEUED,
          metadata: input.metadata,
        },
        select: { id: true },
      });
      return row.id;
    } catch (error) {
      this.logger.error(
        `Failed to create EmailLog for template "${input.template}": ${(error as Error).message}`,
      );
      return undefined;
    }
  }

  async markSent(input: MarkSentInput): Promise<void> {
    await this.safeUpdate(input.id, {
      status: EmailStatus.SENT,
      provider: input.provider,
      providerMessageId: input.providerMessageId,
      attempts: input.attempts,
      sentAt: new Date(),
      error: null,
      metadata: input.metadata,
    });
  }

  async markFailed(input: MarkFailedInput): Promise<void> {
    await this.safeUpdate(input.id, {
      status: input.terminal ? EmailStatus.DEAD_LETTER : EmailStatus.FAILED,
      attempts: input.attempts,
      // Bounded: provider messages are short, but a stack trace leaking in
      // would bloat every row and can contain internal paths.
      error: input.error.slice(0, 1000),
      metadata: input.metadata,
    });
  }

  private async safeUpdate(
    id: string,
    data: Prisma.EmailLogUncheckedUpdateInput,
  ): Promise<void> {
    try {
      await this.prisma.emailLog.update({ where: { id }, data });
    } catch (error) {
      this.logger.error(
        `Failed to update EmailLog ${id}: ${(error as Error).message}`,
      );
    }
  }

  /** Ops view: recent dead-lettered sends, newest first. Served by the
   *  [status, createdAt] composite index. */
  findDeadLettered(limit = 50) {
    return this.prisma.emailLog.findMany({
      where: { status: EmailStatus.DEAD_LETTER },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
  }
}
