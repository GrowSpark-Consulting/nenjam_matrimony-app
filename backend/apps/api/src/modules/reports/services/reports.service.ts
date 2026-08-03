import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ReportsRepository } from '../repositories/reports.repository';
import { CreateReportDto } from '../dto/create-report.dto';
import { ReportResponseDto } from '../dto/report-response.dto';

/**
 * Member-submitted reports (fake profile, harassment, spam, inappropriate
 * content, other). Every report is simply recorded — moderation review/status
 * transitions are an admin-side concern, not implemented here.
 */
@Injectable()
export class ReportsService {
  constructor(private readonly reportsRepository: ReportsRepository) {}

  async report(
    reporterId: string,
    targetUserId: string,
    dto: CreateReportDto,
  ): Promise<ReportResponseDto> {
    if (reporterId === targetUserId) {
      throw new BadRequestException('You cannot report yourself.');
    }
    if (!(await this.reportsRepository.isTargetAvailable(targetUserId))) {
      throw new NotFoundException('This member is no longer available.');
    }

    const report = await this.reportsRepository.create(
      reporterId,
      targetUserId,
      dto.reason,
      dto.description ?? null,
    );

    return {
      id: report.id,
      reason: report.reason,
      status: report.status,
      createdAt: report.createdAt.toISOString(),
    };
  }
}
