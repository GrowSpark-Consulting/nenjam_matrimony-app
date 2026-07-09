import { Injectable } from '@nestjs/common';
import { DecodedIdToken } from 'firebase-admin/auth';
import { FirebaseService } from '@app/firebase';

@Injectable()
export class FirebaseTokenService {
  constructor(private readonly firebaseService: FirebaseService) {}

  /**
   * Verifies a Firebase ID token and returns its decoded claims
   * (uid, email, phone_number, email_verified, among others).
   */
  async verifyIdToken(idToken: string): Promise<DecodedIdToken> {
    return this.firebaseService.verifyIdToken(idToken);
  }
}
