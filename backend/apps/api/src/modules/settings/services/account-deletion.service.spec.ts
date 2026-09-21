import { NotFoundException } from '@nestjs/common';
import { AccountDeletionService } from './account-deletion.service';
import type { PrismaService } from '@app/database';
import type { S3Service } from '@app/storage';
import type { FirebaseService } from '@app/firebase';
import type { RedisService } from '@app/cache';

function build(user: unknown) {
  const findUnique = jest.fn().mockResolvedValue(user);
  const del = jest.fn().mockResolvedValue({});
  const prisma = {
    user: { findUnique, delete: del },
  } as unknown as PrismaService;

  const deleteObjects = jest.fn().mockResolvedValue(undefined);
  const s3 = { deleteObjects } as unknown as S3Service;

  const deleteUser = jest.fn().mockResolvedValue(undefined);
  const firebase = { deleteUser } as unknown as FirebaseService;

  // Cache invalidation is best-effort and fails open: a non-'ready' client
  // makes invalidateCachedUserId a no-op, so these tests exercise the deletion
  // path without needing a live Redis.
  const redisDel = jest.fn().mockResolvedValue(undefined);
  const redis = {
    getClient: () => ({ status: 'end', del: redisDel }),
  } as unknown as RedisService;

  const service = new AccountDeletionService(prisma, s3, firebase, redis);
  return { service, findUnique, del, deleteObjects, deleteUser, redisDel };
}

describe('AccountDeletionService', () => {
  it('deletes every storage object, the Firebase identity, then the user row', async () => {
    const { service, del, deleteObjects, deleteUser } = build({
      firebaseUid: 'fb-uid-1',
      photos: [{ s3Key: 'photos/a.jpg' }, { s3Key: 'photos/b.jpg' }],
      faceVerification: { selfieS3Key: 'kyc/selfie.jpg' },
      kycVerifications: [
        { s3DocKey: 'kyc/aadhaar.pdf' },
        { s3DocKey: 'kyc/income.pdf' },
      ],
    });

    await service.deleteAccount('user-1');

    // All object keys from all three sources, deleted from storage.
    expect(deleteObjects).toHaveBeenCalledWith([
      'photos/a.jpg',
      'photos/b.jpg',
      'kyc/selfie.jpg',
      'kyc/aadhaar.pdf',
      'kyc/income.pdf',
    ]);
    // Firebase identity revoked so the account can never authenticate again.
    expect(deleteUser).toHaveBeenCalledWith('fb-uid-1');
    // The users row is hard-deleted (cascade removes all child tables).
    expect(del).toHaveBeenCalledWith({ where: { id: 'user-1' } });
  });

  it('skips the storage call when the user has no uploaded objects', async () => {
    const { service, del, deleteObjects, deleteUser } = build({
      firebaseUid: 'fb-uid-2',
      photos: [],
      faceVerification: null,
      kycVerifications: [],
    });

    await service.deleteAccount('user-2');

    expect(deleteObjects).not.toHaveBeenCalled();
    expect(deleteUser).toHaveBeenCalledWith('fb-uid-2');
    expect(del).toHaveBeenCalledWith({ where: { id: 'user-2' } });
  });

  // Face verification (liveness) stores no selfie, so a verification row now
  // usually has selfieS3Key = null — that must never reach S3 as a key.
  it('ignores a face verification row that holds no selfie key', async () => {
    const { service, deleteObjects } = build({
      firebaseUid: 'fb-uid-3',
      photos: [{ s3Key: 'profile-photos/user-3/a.jpg' }],
      faceVerification: { selfieS3Key: null },
      kycVerifications: [],
    });

    await service.deleteAccount('user-3');

    expect(deleteObjects).toHaveBeenCalledWith(['profile-photos/user-3/a.jpg']);
  });

  it('throws NotFound (and deletes nothing) when the account is already gone', async () => {
    const { service, del, deleteObjects, deleteUser } = build(null);

    await expect(service.deleteAccount('missing')).rejects.toBeInstanceOf(
      NotFoundException,
    );
    expect(deleteObjects).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
    expect(del).not.toHaveBeenCalled();
  });
});
