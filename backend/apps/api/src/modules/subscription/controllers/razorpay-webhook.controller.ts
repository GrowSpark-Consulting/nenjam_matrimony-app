import {
  Body,
  Controller,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import type { RawBodyRequest } from '@nestjs/common';
import type { Request } from 'express';
import { ApiExcludeController } from '@nestjs/swagger';
import { RazorpaySignatureGuard } from '../guards/razorpay-signature.guard';
import {
  RazorpayWebhookService,
  type WebhookResult,
} from '../services/razorpay-webhook.service';

// Called by Razorpay, not by members — so no FirebaseAuthGuard. Authenticated
// instead by RazorpaySignatureGuard (HMAC of the raw body); 503 until the
// webhook secret is configured. Always 200 once accepted (duplicates too), so
// Razorpay stops retrying; a 5xx means "not applied, retry".
@ApiExcludeController()
@Controller('payments/razorpay')
export class RazorpayWebhookController {
  constructor(private readonly webhooks: RazorpayWebhookService) {}

  @Post('webhook')
  @HttpCode(HttpStatus.OK)
  @UseGuards(RazorpaySignatureGuard)
  handle(
    @Req() request: RawBodyRequest<Request>,
    @Headers('x-razorpay-event-id') eventId: string | undefined,
    @Body() body: unknown,
  ): Promise<WebhookResult> {
    // The guard has already refused any request without a raw body.
    return this.webhooks.handle(eventId, body, request.rawBody!);
  }
}
