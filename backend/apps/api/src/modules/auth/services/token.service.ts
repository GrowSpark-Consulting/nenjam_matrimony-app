import { Injectable } from '@nestjs/common';
import { JwtService, JwtSignOptions } from '@nestjs/jwt';
import { User } from '@app/database';

type ExpiresIn = JwtSignOptions['expiresIn'];

export type JwtTokenType = 'access' | 'refresh';

export interface JwtPayload {
  userId: string;
  firebaseUid: string;
  phoneNumber: string | null;
  type: JwtTokenType;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

// Mirrors JWT_ACCESS_EXPIRY / JWT_REFRESH_EXPIRY in .env — kept as code
// constants for now since only JWT_SECRET is wired through AppConfigService.
const ACCESS_TOKEN_EXPIRY: ExpiresIn = '15m';
const REFRESH_TOKEN_EXPIRY: ExpiresIn = '7d';

@Injectable()
export class TokenService {
  constructor(private readonly jwtService: JwtService) {}

  generateAccessToken(user: User): string {
    return this.sign(user, 'access', ACCESS_TOKEN_EXPIRY);
  }

  generateRefreshToken(user: User): string {
    return this.sign(user, 'refresh', REFRESH_TOKEN_EXPIRY);
  }

  generateTokenPair(user: User): TokenPair {
    return {
      accessToken: this.generateAccessToken(user),
      refreshToken: this.generateRefreshToken(user),
    };
  }

  private sign(user: User, type: JwtTokenType, expiresIn: ExpiresIn): string {
    const payload: JwtPayload = {
      userId: user.id,
      firebaseUid: user.firebaseUid,
      phoneNumber: user.phone,
      type,
    };
    return this.jwtService.sign(payload, { expiresIn });
  }
}
