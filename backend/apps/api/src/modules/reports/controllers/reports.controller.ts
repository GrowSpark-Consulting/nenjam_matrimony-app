import { Body, Controller, Param, Post, UseGuards } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiCreatedResponse,
  ApiNotFoundResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { ReportsService } from '../services/reports.service';
import { CreateReportDto } from '../dto/create-report.dto';
import {
  REPORT_RESPONSE_EXAMPLE,
  ReportResponseDto,
} from '../dto/report-response.dto';

// Report a member for moderation review. Every route is user-scoped via the
// verified Firebase token — a caller only ever reports on their own behalf.
@ApiTags('Reports')
@ApiBearerAuth('firebase')
@ApiUnauthorizedResponse({
  description: 'Missing or invalid Firebase ID token.',
})
@Controller('users')
@UseGuards(FirebaseAuthGuard)
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Post(':id/report')
  @ApiOperation({
    summary: 'Report a member',
    description:
      'Flags a member for moderation review (fake profile, harassment, spam, ' +
      'inappropriate content, or other). Does not block the member — send a ' +
      'separate block request if the reporter also wants that.',
  })
  @ApiParam({ name: 'id', description: 'The member (user) id being reported.' })
  @ApiCreatedResponse({
    description: 'The created report.',
    schema: { example: REPORT_RESPONSE_EXAMPLE },
  })
  @ApiBadRequestResponse({ description: 'You cannot report yourself.' })
  @ApiNotFoundResponse({
    description: 'Member not found or no longer available.',
  })
  report(
    @CurrentUser('id') userId: string,
    @Param('id') targetUserId: string,
    @Body() dto: CreateReportDto,
  ): Promise<ReportResponseDto> {
    return this.reportsService.report(userId, targetUserId, dto);
  }
}
