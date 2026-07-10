import { User } from '@app/database';

export class AuthTokensResponseDto {
  accessToken!: string;
  refreshToken!: string;
  user!: User;
  needsEmailVerification!: boolean;
}
