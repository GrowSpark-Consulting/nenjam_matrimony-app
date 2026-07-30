import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  ReportReason,
  UserReport,
} from '../../../../../../libs/database/generated/client';

@Injectable()
export class ReportsRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** Whether the target user is a live account (exists and not soft-deleted). */
  async isTargetAvailable(targetUserId: string): Promise<boolean> {
    const user = await this.prisma.user.findUnique({
      where: { id: targetUserId },
      select: { deletedAt: true },
    });
    return Boolean(user) && !user!.deletedAt;
  }

  create(
    reporterId: string,
    reportedUserId: string,
    reason: ReportReason,
    description: string | null,
  ): Promise<UserReport> {
    return this.prisma.userReport.create({
      data: { reporterId, reportedUserId, reason, description },
    });
  }
}
