import { Injectable } from '@nestjs/common';
import { DecodedIdToken } from 'firebase-admin/auth';
import { Prisma, User } from '@app/database';
import { AuthRepository } from '../repositories/auth.repository';
import { FirebaseTokenService } from './firebase-token.service';
import { TokenService, TokenPair } from './token.service';

export interface FirebaseAuthResult extends TokenPair {
  user: User;
  needsEmailVerification: boolean;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly authRepository: AuthRepository,
    private readonly firebaseTokenService: FirebaseTokenService,
    private readonly tokenService: TokenService,
  ) {}

  /**
   * Verifies a Firebase ID token, synchronizes the Prisma user record,
   * and issues a backend JWT pair for it.
   */
  async authenticateWithFirebase(idToken: string): Promise<FirebaseAuthResult> {
    const decodedToken = await this.firebaseTokenService.verifyIdToken(idToken);
    const user = await this.findOrCreateUser(decodedToken);
    const { accessToken, refreshToken } =
      this.tokenService.generateTokenPair(user);

    return {
      accessToken,
      refreshToken,
      user,
      needsEmailVerification: !user.email || !user.emailVerified,
    };
  }

  async findOrCreateUser(decodedToken: DecodedIdToken): Promise<User> {
    const existing = await this.authRepository.findByFirebaseUid(
      decodedToken.uid,
    );
    if (existing) {
      return this.authRepository.update(
        existing.id,
        this.buildUpdateData(decodedToken),
      );
    }

    try {
      return await this.authRepository.create({
        firebaseUid: decodedToken.uid,
        phone: decodedToken.phone_number ?? null,
        email: decodedToken.email ?? null,
        emailVerified: Boolean(decodedToken.email_verified),
      });
    } catch (error) {
      // Concurrent first login: another request already created this user
      // between our lookup and this insert — return the winning row instead
      // of failing the second request on the unique firebaseUid constraint.
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        const winner = await this.authRepository.findByFirebaseUid(
          decodedToken.uid,
        );
        if (winner) {
          return winner;
        }
      }
      throw error;
    }
  }

  // Phone is synced whenever Firebase reports one; email/emailVerified are
  // only touched when Firebase provides an email — an existing email must
  // never be cleared by a token that doesn't carry one (e.g. a phone-only
  // re-login after email linking).
  private buildUpdateData(
    decodedToken: DecodedIdToken,
  ): Prisma.UserUpdateInput {
    const data: Prisma.UserUpdateInput = {};

    if (decodedToken.phone_number) {
      data.phone = decodedToken.phone_number;
    }

    if (decodedToken.email) {
      data.email = decodedToken.email;
      data.emailVerified = Boolean(decodedToken.email_verified);
    }

    return data;
  }
}
