import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsOptional, IsString, Matches } from 'class-validator';

/**
 * The identifiers a member finished the dummy-OTP step with.
 *
 * The phone is required and the email optional because the phone is what the
 * step verifies (however loosely) and therefore what the account is keyed on —
 * the address is carried along so that an email signup ends up on the same
 * single account rather than a second one.
 */
export class DummyOtpSessionRequestDto {
  /** E.164, the same representation the app stores and sends everywhere else. */
  @ApiProperty({ example: '+919876543210' })
  @IsString()
  @Matches(/^\+[1-9]\d{7,14}$/, {
    message: 'phone must be in E.164 format, e.g. +919876543210',
  })
  phone!: string;

  @ApiPropertyOptional({ example: 'someone@example.com' })
  @IsOptional()
  @IsEmail({}, { message: 'email must be a valid address' })
  email?: string;
}

/**
 * A real Firebase credential, and the uid it belongs to.
 *
 * The uid is returned so the client can assert that the session it ends up
 * holding is the one the backend provisioned — the whole failure this endpoint
 * exists to close was a client that believed it was signed in as an identity
 * the backend had never heard of.
 */
export class DummyOtpSessionResponseDto {
  @ApiProperty({ description: 'Exchange via signInWithCustomToken().' })
  customToken!: string;

  @ApiProperty({ description: 'The Firebase UID this token signs in as.' })
  uid!: string;

  @ApiProperty({ description: 'The internal users.id mapped to that UID.' })
  userId!: string;
}
