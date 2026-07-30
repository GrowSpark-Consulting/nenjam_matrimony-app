import { ApiProperty } from '@nestjs/swagger';
import { IsIn, IsNotEmpty, IsString } from 'class-validator';
import type { DevicePlatform } from '../../../../../../libs/database/generated/client';

export const DEVICE_PLATFORMS = ['ANDROID', 'IOS'] as const;

/** Body for POST /notifications/device — registers (or re-activates) an FCM
 *  token for the calling user's device. Re-registering an existing token
 *  (app reinstall, token refresh) retargets/reactivates it rather than
 *  erroring, since `fcmToken` is globally unique. */
export class RegisterDeviceDto {
  @ApiProperty({
    description: 'The FCM registration token for this device.',
    example: 'dGhpcyBpcyBhIHRva2Vu...',
  })
  @IsString()
  @IsNotEmpty()
  fcmToken!: string;

  @ApiProperty({ description: 'Device platform.', enum: DEVICE_PLATFORMS })
  @IsIn(DEVICE_PLATFORMS)
  platform!: DevicePlatform;
}

/** Body for DELETE /notifications/device — `fcmToken` is sent in the request
 *  body, matching the DELETE /matches/shortlist convention already used in
 *  this codebase. */
export class UnregisterDeviceDto {
  @ApiProperty({
    description: 'The FCM registration token to deactivate.',
    example: 'dGhpcyBpcyBhIHRva2Vu...',
  })
  @IsString()
  @IsNotEmpty()
  fcmToken!: string;
}
