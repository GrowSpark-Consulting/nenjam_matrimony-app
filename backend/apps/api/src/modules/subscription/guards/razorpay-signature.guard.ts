import {
  CanActivate,
  ExecutionContext,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import type { RawBodyRequest } from '@nestjs/common';
import type { Request } from 'express';
import { RazorpayService } from '../services/razorpay.service';

/**
 * Authenticates a Razorpay webhook delivery: the X-Razorpay-Signature header
 * must be the HMAC-SHA256 of the exact raw request body under the webhook
 * secret. This replaces FirebaseAuthGuard on the one route Razorpay (not a
 * member) calls — an unsigned or tampered request never reaches the handler.
 *
 * Needs the raw body, which main.ts keeps (`rawBody: true`); re-serialising
 * the parsed JSON would not reproduce the signed bytes.
 */
@Injectable()
export class RazorpaySignatureGuard implements CanActivate {
  constructor(private readonly razorpay: RazorpayService) {}

  canActivate(context: ExecutionContext): boolean {
    if (!this.razorpay.isWebhookConfigured()) {
      throw new ServiceUnavailableException(
        'Payment webhooks are not configured.',
      );
    }
    const request = context
      .switchToHttp()
      .getRequest<RawBodyRequest<Request>>();
    const signature = request.headers['x-razorpay-signature'];
    if (
      typeof signature !== 'string' ||
      !request.rawBody ||
      !this.razorpay.verifyWebhookSignature(request.rawBody, signature)
    ) {
      throw new UnauthorizedException('Invalid webhook signature.');
    }
    return true;
  }
}
