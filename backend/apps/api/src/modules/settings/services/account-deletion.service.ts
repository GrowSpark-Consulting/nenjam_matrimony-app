import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '@app/database';
import { S3Service } from '@app/storage';
import { FirebaseService } from '@app/firebase';

/**
 * Hard account deletion. Permanently removes every trace of a user:
 *   - all uploaded storage objects (profile photos, KYC documents, the face
 *     verification selfie) — the S3 keys live in rows the DB cascade is about
 *     to delete, so they MUST be collected first;
 *   - the Firebase Auth identity (so the account can never authenticate again);
 *   - the users row — a single statement whose `onDelete: Cascade` FKs remove
 *     every child table (profile, registration draft, partner preferences,
 *     notifications, chats/messages, interests, shortlists, profile views,
 *     subscriptions, payments, KYC/face verification, blocks, reports, refresh
 *     tokens, device push tokens, quiz responses, …). No orphan rows remain.
 *
 * Ordering (storage → auth → DB) is deliberate: deleting the DB row first would
 * lose the storage keys and orphan the files — the exact "old photo re-appears
 * after re-registration" bug this fixes. Storage/auth cleanup is best-effort and
 * logged (see S3Service / FirebaseService); it never blocks the DB delete, so a
 * user can always remove their account even if the object store or auth provider
 * is briefly unavailable (any residue is logged for a later sweep).
 */
@Injectable()
export class AccountDeletionService {
  private readonly logger = new Logger(AccountDeletionService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly s3: S3Service,
    private readonly firebase: FirebaseService,
  ) {}

  async deleteAccount(userId: string): Promise<void> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        firebaseUid: true,
        photos: { select: { s3Key: true } },
        faceVerification: { select: { selfieS3Key: true } },
        kycVerifications: { select: { s3DocKey: true } },
      },
    });

    if (!user) {
      // Idempotent guard: the account is already gone (e.g. a retried request).
      throw new NotFoundException('Account not found or already deleted.');
    }

    const objectKeys = [
      ...user.photos.map((p) => p.s3Key),
      ...(user.faceVerification ? [user.faceVerification.selfieS3Key] : []),
      ...user.kycVerifications.map((k) => k.s3DocKey),
    ].filter((key): key is string => Boolean(key));

    // 1. Storage — not reachable by the DB cascade; orphaned files are the bug.
    if (objectKeys.length > 0) {
      await this.s3.deleteObjects(objectKeys);
      this.logger.log(
        `Requested deletion of ${objectKeys.length} storage object(s) for account ${userId}.`,
      );
    }

    // 2. Auth — the deleted account must not be able to sign in again.
    await this.firebase.deleteUser(user.firebaseUid);

    // 3. Database — one atomic cascade delete of the user and every child row.
    await this.prisma.user.delete({ where: { id: userId } });

    this.logger.log(
      `Hard-deleted account ${userId} (database + ${objectKeys.length} storage object(s) + auth).`,
    );
  }
}
