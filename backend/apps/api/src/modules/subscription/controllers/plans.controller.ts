import {
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import {
  ApiBearerAuth,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { WRITE_LIMIT } from '../../../throttling';
import { PlansService } from '../services/plans.service';
import { SubscriptionLifecycleService } from '../services/subscription-lifecycle.service';
import type {
  CancelSubscriptionResponseDto,
  MyMembershipResponseDto,
  PlanCatalogResponseDto,
  SubscriptionHistoryItemDto,
} from '../dto/plan.response.dto';

// Member-facing membership reads and self-service. Every route is scoped to
// the caller by the verified Firebase token; nothing here can read or change
// another member's plan, and nothing here changes the catalogue (that is
// PlanCatalogAdminService, which has no HTTP surface yet).
@ApiTags('Membership')
@ApiBearerAuth('firebase')
@ApiUnauthorizedResponse({
  description: 'Missing or invalid Firebase ID token.',
})
@Controller('membership')
@UseGuards(FirebaseAuthGuard)
export class PlansController {
  constructor(
    private readonly plansService: PlansService,
    private readonly lifecycle: SubscriptionLifecycleService,
  ) {}

  @Get('plans')
  @ApiOperation({
    summary: 'The plans on offer',
    description:
      'Active plans with what each grants (keyed by stable feature ids, described in `features`) and the durations on sale.',
  })
  @ApiOkResponse({ description: 'Plan catalogue.' })
  plans(): Promise<PlanCatalogResponseDto> {
    return this.plansService.listPlans();
  }

  @Get('me')
  @ApiOperation({
    summary: "The caller's membership",
    description:
      'Current plan, subscription, entitlements and usage against every metered allowance. Members with no subscription are Free.',
  })
  @ApiOkResponse({ description: 'The caller’s membership.' })
  me(@CurrentUser('id') userId: string): Promise<MyMembershipResponseDto> {
    return this.plansService.myMembership(userId);
  }

  @Get('history')
  @ApiOperation({
    summary: "The caller's purchases",
    description:
      'Every subscription bought or granted, newest first, with its payments.',
  })
  history(
    @CurrentUser('id') userId: string,
  ): Promise<SubscriptionHistoryItemDto[]> {
    return this.plansService.history(userId);
  }

  @Throttle(WRITE_LIMIT)
  @Post('subscription/cancel')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Stop renewal',
    description:
      'Turns off renewal for the caller’s paid plans. Access continues until each plan’s end date.',
  })
  @ApiNotFoundResponse({ description: 'No active paid plan.' })
  async cancel(
    @CurrentUser('id') userId: string,
  ): Promise<CancelSubscriptionResponseDto> {
    const { cancelled, accessUntil } =
      await this.lifecycle.cancelAtPeriodEnd(userId);
    return { cancelled, accessUntil: accessUntil.toISOString() };
  }
}
