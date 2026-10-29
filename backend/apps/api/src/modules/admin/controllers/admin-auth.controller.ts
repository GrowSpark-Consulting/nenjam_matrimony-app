import { Body, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '@app/common';
import {
  AdminContext,
  type AdminRequestContext,
  type AuthenticatedAdmin,
  CurrentAdmin,
} from '../auth/admin-request';
import {
  AdminController,
  AdminSessionNotRequired,
  AllowAnyAdmin,
} from '../auth/admin-route.decorators';
import {
  AdminEnrollmentConfirmDto,
  AdminEnrollmentResponseDto,
  AdminEnrollmentStartDto,
  AdminSessionResponseDto,
  AdminTotpCodeDto,
} from '../dto/admin-auth.dto';
import { AdminMfaService } from '../services/admin-mfa.service';

/**
 * The second factor. Each route needs a valid Firebase ID token for an active
 * staff account; the sign-in steps are the only admin routes that don't also
 * need an admin session. Tightly rate limited per IP on top of the per-account
 * lockout.
 */
@AdminController('admin/auth')
@Throttle({ default: { limit: 10, ttl: 15 * 60_000 } })
export class AdminAuthController {
  constructor(private readonly mfa: AdminMfaService) {}

  @Post('mfa/enrollment')
  @AdminSessionNotRequired()
  @ApiOperation({
    summary: 'Start authenticator enrolment with the one-time enrolment code',
  })
  startEnrollment(
    @CurrentUser('id') userId: string,
    @Body() body: AdminEnrollmentStartDto,
    @AdminContext() context: AdminRequestContext,
  ): Promise<AdminEnrollmentResponseDto> {
    return this.mfa.beginEnrollment(userId, body.enrollmentCode, context);
  }

  @Post('mfa/enrollment/confirm')
  @AdminSessionNotRequired()
  @ApiOperation({
    summary: 'Confirm enrolment with the first authenticator code; signs in',
  })
  confirmEnrollment(
    @CurrentUser('id') userId: string,
    @Body() body: AdminEnrollmentConfirmDto,
    @AdminContext() context: AdminRequestContext,
  ): Promise<AdminSessionResponseDto> {
    return this.mfa.confirmEnrollment(
      userId,
      body.enrollmentCode,
      body.code,
      context,
    );
  }

  @Post('session')
  @AdminSessionNotRequired()
  @ApiOperation({
    summary: 'Sign in: exchange an authenticator code for an admin session',
  })
  signIn(
    @CurrentUser('id') userId: string,
    @Body() body: AdminTotpCodeDto,
    @AdminContext() context: AdminRequestContext,
  ): Promise<AdminSessionResponseDto> {
    return this.mfa.signIn(userId, body.code, context);
  }

  @Post('step-up')
  @HttpCode(HttpStatus.OK)
  @AllowAnyAdmin()
  @ApiOperation({
    summary: 'Re-confirm with a fresh code before a sensitive action',
  })
  stepUp(
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @Body() body: AdminTotpCodeDto,
    @AdminContext() context: AdminRequestContext,
  ): Promise<{ stepUpValidUntil: Date }> {
    return this.mfa.stepUp(admin, body.code, context);
  }

  @Post('logout')
  @HttpCode(HttpStatus.NO_CONTENT)
  @AllowAnyAdmin()
  @ApiOperation({ summary: 'End the current admin session' })
  async logout(
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ): Promise<void> {
    await this.mfa.logout(admin, context);
  }
}
