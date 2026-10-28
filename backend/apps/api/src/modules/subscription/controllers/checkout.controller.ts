import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiOperation,
  ApiServiceUnavailableResponse,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { WRITE_LIMIT } from '../../../throttling';
import { CheckoutService } from '../services/checkout.service';
import {
  CheckoutDto,
  VerifyCheckoutDto,
  type CheckoutResponseDto,
  type VerifyCheckoutResponseDto,
} from '../dto/checkout.dto';

// Buying a plan. Both routes answer 503 until Razorpay is configured.
@ApiTags('Membership')
@ApiBearerAuth('firebase')
@ApiUnauthorizedResponse({
  description: 'Missing or invalid Firebase ID token.',
})
@ApiServiceUnavailableResponse({ description: 'Payments are not configured.' })
@Controller('membership/checkout')
@UseGuards(FirebaseAuthGuard)
export class CheckoutController {
  constructor(private readonly checkoutService: CheckoutService) {}

  @Throttle(WRITE_LIMIT)
  @Post()
  @ApiOperation({
    summary: 'Start buying a plan',
    description:
      'Creates a Razorpay order at the current price. Open Razorpay Checkout with the returned `keyId` and `orderId`, then call /verify. Nothing is granted until payment is confirmed.',
  })
  @ApiBadRequestResponse({ description: 'Plan or duration not on sale.' })
  start(
    @CurrentUser('id') userId: string,
    @Body() dto: CheckoutDto,
  ): Promise<CheckoutResponseDto> {
    return this.checkoutService.start(userId, dto);
  }

  @Throttle(WRITE_LIMIT)
  @Post('verify')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Confirm a payment',
    description:
      'Verifies the Razorpay signature server-side and activates the plan. Idempotent — safe to retry, and safe to race the webhook.',
  })
  @ApiBadRequestResponse({ description: 'Signature did not verify.' })
  verify(
    @CurrentUser('id') userId: string,
    @Body() dto: VerifyCheckoutDto,
  ): Promise<VerifyCheckoutResponseDto> {
    return this.checkoutService.verify(userId, dto);
  }
}
