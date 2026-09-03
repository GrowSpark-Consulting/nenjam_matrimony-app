import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { DummyOtpSessionService } from '../services/dummy-otp-session.service';
import {
  DummyOtpSessionRequestDto,
  DummyOtpSessionResponseDto,
} from '../dto/dummy-otp-session.dto';

/**
 * Exchanges a passed dummy OTP for a real Firebase session.
 *
 * **Deliberately unauthenticated**, like the account-availability check beside
 * it: it is called from the OTP screen, which is the moment *before* the member
 * has any credential — that is the whole point of it.
 *
 * What keeps that safe is not a token but the policy in `dev-auth.ts`, which
 * this shares with the `X-Dev-Auth-Phone` header it replaces: off unless an
 * operator set a flag, a whitelist in production, and off entirely once
 * `USE_REAL_OTP=true`. Rate limited at the same tight tier as
 * account-availability, because an open endpoint that mints sessions must not
 * also be somewhere to grind through numbers.
 *
 * Delete this controller together with `MockOtpVerifier` and `dev-auth.ts` when
 * real phone verification is switched on — the client will then get its session
 * from Firebase directly and none of this is needed.
 */
@ApiTags('accounts')
@Controller('auth')
export class DummyOtpSessionController {
  constructor(private readonly sessions: DummyOtpSessionService) {}

  @Post('dummy-otp/session')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOperation({
    summary: 'Exchange a passed dummy OTP for a Firebase custom token',
  })
  @ApiOkResponse({ type: DummyOtpSessionResponseDto })
  async start(
    @Body() body: DummyOtpSessionRequestDto,
  ): Promise<DummyOtpSessionResponseDto> {
    return this.sessions.start({ phone: body.phone, email: body.email });
  }
}
