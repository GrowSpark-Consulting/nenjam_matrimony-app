import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';
import type { PaymentDiscountSource } from '@app/common';
import type {
  SubscriptionPlanName,
  SubscriptionStatus,
} from '../../../../../../libs/database/generated/client';
import type { ActivationOutcome } from '../services/subscription-lifecycle.service';

export const PURCHASABLE_PLAN_CODES = ['GOLD', 'PLATINUM'] as const;

/** Body for POST /membership/checkout. Which lengths are actually on sale
 *  is the catalogue's call, not the DTO's — this only bounds the shape. */
export class CheckoutDto {
  @ApiProperty({ enum: PURCHASABLE_PLAN_CODES, example: 'GOLD' })
  @IsIn(PURCHASABLE_PLAN_CODES)
  planCode!: (typeof PURCHASABLE_PLAN_CODES)[number];

  @ApiProperty({ example: 3, description: 'Plan length in months.' })
  @Type(() => Number)
  @IsInt()
  @IsIn([1, 3, 6, 12, 24])
  months!: number;

  @ApiPropertyOptional({
    example: 'NM7K2P9X',
    description:
      'A referral code the member typed. Refused (422) if it gives no discount; leave it out otherwise.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(32)
  promoCode?: string;
}

/** Body for POST /membership/checkout/verify — exactly the three values the
 *  Razorpay Checkout success handler returns. */
export class VerifyCheckoutDto {
  @ApiProperty({ example: 'order_N1x2y3z4' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  orderId!: string;

  @ApiProperty({ example: 'pay_N1x2y3z4' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  paymentId!: string;

  @ApiProperty({ description: 'razorpay_signature (hex HMAC-SHA256).' })
  @IsString()
  @Matches(/^[0-9a-f]{64}$/i)
  signature!: string;
}

export interface CheckoutResponseDto {
  subscriptionId: string;
  /** Pass to Razorpay Checkout as `order_id`. */
  orderId: string;
  amountInPaise: number;
  currency: string;
  /** Pass to Razorpay Checkout as `key`. Public by design. */
  keyId: string;
  plan: { code: SubscriptionPlanName; name: string };
  months: number;
  /** How amountInPaise was reached; show it before payment. */
  pricing: CheckoutPricingDto;
  /** Present when a referral discount applies. */
  referral: { agentDisplayName: string | null } | null;
}

/** All in paise. GST is added on top: total = list − discount + tax. */
export interface CheckoutPricingDto {
  /** The plan price, excluding GST. */
  listAmountPaise: number;
  discountPaise: number;
  discountSource: PaymentDiscountSource;
  taxableAmountPaise: number;
  /** 1800 = 18%; 0 while the business is not GST-registered. */
  taxRateBps: number;
  taxPaise: number;
  /** = amountInPaise: what the member pays. */
  totalPaise: number;
}

/**
 * What POST /membership/checkout/verify concluded:
 *  - ACTIVATED / ALREADY_APPLIED — the plan is (now) active or queued; read
 *    `status`/dates, then refresh GET /membership/me.
 *  - AWAITING_CAPTURE / PENDING_CONFIRMATION — money not confirmed yet
 *    (not captured, or Razorpay unreachable). Nothing granted; the webhook
 *    activates it. Poll GET /membership/me.
 *  - NOT_PAID / REFUNDED / AMOUNT_MISMATCH / PAID_NOT_ACTIVATED — nothing
 *    granted; show an error (the last two also alert operators via logs).
 */
export type VerifyOutcome =
  ActivationOutcome | 'AWAITING_CAPTURE' | 'PENDING_CONFIRMATION' | 'NOT_PAID';

export interface VerifyCheckoutResponseDto {
  outcome: VerifyOutcome;
  subscriptionId: string;
  status: SubscriptionStatus;
  startDate: string | null;
  endDate: string | null;
}
