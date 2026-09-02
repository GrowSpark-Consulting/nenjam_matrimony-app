import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { FirebaseService } from '@app/firebase';
import {
  AccountExistsRequestDto,
  AccountExistsResponseDto,
} from '../dto/account-exists.dto';

/**
 * Tells a signup screen whether an email or mobile number is already taken.
 *
 * **Deliberately unauthenticated** — it is called from the Email + Mobile
 * onboarding step, which runs before an account exists, so there is no token
 * to present. Every other controller opts into `FirebaseAuthGuard`; this one
 * cannot, and is kept to the narrowest possible surface in exchange:
 *
 *  - it answers only yes/no per identifier, never with account details;
 *  - it is rate-limited well below the default, because an open
 *    "does this address have an account?" endpoint is an enumeration oracle
 *    and the limit is the only thing standing between it and a mailing list.
 *
 * A failed lookup deliberately surfaces as a 5xx rather than "available":
 * reporting a taken identifier as free is what creates duplicate accounts.
 */
@ApiTags('accounts')
@Controller('auth')
export class AccountAvailabilityController {
  constructor(private readonly firebase: FirebaseService) {}

  @Post('account-exists')
  @HttpCode(HttpStatus.OK)
  // Tighter than the global default: enough for a member correcting a typo,
  // far too slow to enumerate with.
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOperation({
    summary: 'Whether an email or mobile already belongs to an account',
  })
  @ApiOkResponse({ type: AccountExistsResponseDto })
  async accountExists(
    @Body() body: AccountExistsRequestDto,
  ): Promise<AccountExistsResponseDto> {
    return this.firebase.accountExists({
      email: body.email,
      phone: body.phone,
    });
  }
}
