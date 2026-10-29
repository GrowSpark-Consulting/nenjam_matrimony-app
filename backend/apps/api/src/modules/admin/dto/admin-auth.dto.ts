import { ApiProperty } from '@nestjs/swagger';
import { IsString, Length, Matches } from 'class-validator';

const TOTP_CODE = /^\d{6}$/;

export class AdminEnrollmentStartDto {
  @ApiProperty({
    description: 'One-time code printed by `pnpm admin:provision`.',
    example: 'K7Q2M-XR9TB',
  })
  @IsString()
  @Length(10, 16)
  enrollmentCode!: string;
}

export class AdminEnrollmentConfirmDto extends AdminEnrollmentStartDto {
  @ApiProperty({
    description: 'Current 6-digit code from the authenticator app.',
  })
  @Matches(TOTP_CODE, { message: 'code must be 6 digits' })
  code!: string;
}

export class AdminTotpCodeDto {
  @ApiProperty({
    description: 'Current 6-digit code from the authenticator app.',
  })
  @Matches(TOTP_CODE, { message: 'code must be 6 digits' })
  code!: string;
}

export class AdminSessionResponseDto {
  @ApiProperty({
    description:
      'Send as the X-Admin-Session header on every admin request. Shown once.',
  })
  sessionToken!: string;

  @ApiProperty({ description: 'Absolute end of the session.' })
  expiresAt!: Date;

  @ApiProperty({ description: 'The session also ends after this long idle.' })
  idleTimeoutSeconds!: number;
}

export class AdminEnrollmentResponseDto {
  @ApiProperty({
    description: 'Base32 secret, for typing into the app by hand.',
  })
  secret!: string;

  @ApiProperty({ description: 'otpauth:// URI, for showing as a QR code.' })
  otpauthUri!: string;
}

export class AdminMeResponseDto {
  @ApiProperty() adminAccountId!: string;
  @ApiProperty() userId!: string;
  @ApiProperty() email!: string;
  @ApiProperty() department!: string;
  @ApiProperty({ nullable: true, type: Date }) lastLoginAt!: Date | null;
  @ApiProperty({ type: [Object] }) roles!: Array<{ key: string; name: string }>;
  @ApiProperty({
    type: [String],
    description:
      'Permission keys this admin holds; the panel shows only what these allow.',
  })
  permissions!: string[];
}
