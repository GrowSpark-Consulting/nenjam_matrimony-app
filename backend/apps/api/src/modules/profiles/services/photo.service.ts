import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { S3Service, StoragePrefix } from '@app/storage';
import { PhotoRepository } from '../repositories/photo.repository';
import { PhotoEntity } from '../entities/photo.entity';
import { ProfileService } from './profile.service';
import { extensionForMime, UploadedImageFile } from '../pipes/photo-file.pipe';

const MAX_PHOTOS_PER_USER = 6;

@Injectable()
export class PhotoService {
  private readonly logger = new Logger(PhotoService.name);

  constructor(
    private readonly photoRepository: PhotoRepository,
    private readonly s3: S3Service,
    private readonly profileService: ProfileService,
  ) {}

  /**
   * The user's photos, each with a fresh presigned GET URL in `cdnUrl` so the
   * client can display private objects without the bucket being public.
   */
  async list(userId: string): Promise<PhotoEntity[]> {
    const photos = await this.photoRepository.findAllForUser(userId);
    return this.withPresignedUrls(photos);
  }

  /**
   * Uploads a new photo: validates the count cap, stores the binary in S3,
   * then records metadata. If the DB write fails after the object is stored,
   * the orphaned object is deleted so storage and DB never diverge.
   */
  async upload(
    userId: string,
    file: UploadedImageFile,
    isPrimary?: boolean,
  ): Promise<PhotoEntity> {
    const existingCount = await this.photoRepository.countForUser(userId);
    if (existingCount >= MAX_PHOTOS_PER_USER) {
      throw new BadRequestException(
        `Cannot upload more than ${MAX_PHOTOS_PER_USER} photos.`,
      );
    }

    const key = this.buildKey(userId, file.mimetype);
    await this.s3.uploadObject({
      key,
      body: file.buffer,
      contentType: file.mimetype,
    });

    try {
      const created = await this.photoRepository.create(userId, {
        s3Key: key,
        cdnUrl: this.s3.getObjectUrl(key),
        isPrimary: isPrimary ?? existingCount === 0,
        order: existingCount,
      });
      this.logger.log(`User ${userId} uploaded photo ${created.id}.`);
      // The "photos" completion slice (12%) flips on count > 0 — only
      // matters on the first photo, but recalculating unconditionally
      // avoids tracking "was this the first" here and keeps
      // UserProfile.profileCompletePct (read directly by Discover's
      // feed mapper) from ever going stale. Never fails the upload itself.
      await this.profileService.recalculateCompletionIfMaterialized(userId);
      return this.attachPresignedUrl(created);
    } catch (error) {
      // DB write failed — remove the just-stored object so it can't orphan.
      this.logger.error(
        `DB write failed after S3 upload for user ${userId}; rolling back object ${key}: ${(error as Error).message}`,
      );
      await this.s3.deleteObject(key);
      throw error;
    }
  }

  /**
   * Replaces the binary of an existing photo, preserving its id/order/primary
   * flag. Uploads the new object first, repoints the row, then deletes the old
   * object; if the DB update fails the new object is rolled back.
   */
  async replace(
    userId: string,
    photoId: string,
    file: UploadedImageFile,
  ): Promise<PhotoEntity> {
    const existing = await this.photoRepository.findByIdForUser(
      photoId,
      userId,
    );
    if (!existing) {
      throw new NotFoundException('Photo not found.');
    }

    const newKey = this.buildKey(userId, file.mimetype);
    await this.s3.uploadObject({
      key: newKey,
      body: file.buffer,
      contentType: file.mimetype,
    });

    let updated: PhotoEntity;
    try {
      updated = await this.photoRepository.updateStorage(photoId, {
        s3Key: newKey,
        cdnUrl: this.s3.getObjectUrl(newKey),
      });
    } catch (error) {
      this.logger.error(
        `DB update failed during replace for photo ${photoId}; rolling back new object ${newKey}: ${(error as Error).message}`,
      );
      await this.s3.deleteObject(newKey);
      throw error;
    }

    // Success — the old object is now unreferenced; best-effort delete.
    await this.s3.deleteObject(existing.s3Key);
    this.logger.log(`User ${userId} replaced photo ${photoId}.`);
    return this.attachPresignedUrl(updated);
  }

  /**
   * Deletes a photo (DB row + S3 object). If the removed photo was primary and
   * others remain, the lowest-order remaining photo is promoted so the user
   * always has a display photo. Returns the remaining list.
   */
  async remove(userId: string, photoId: string): Promise<PhotoEntity[]> {
    const existing = await this.photoRepository.findByIdForUser(
      photoId,
      userId,
    );
    if (!existing) {
      throw new NotFoundException('Photo not found.');
    }

    await this.photoRepository.deleteById(photoId);
    await this.s3.deleteObject(existing.s3Key);

    if (existing.isPrimary) {
      await this.photoRepository.promoteFirstToPrimary(userId);
    }
    // Deleting the user's last photo must drop the "photos" completion
    // slice (12%) back to 0 — see the matching comment in upload().
    await this.profileService.recalculateCompletionIfMaterialized(userId);
    this.logger.log(`User ${userId} deleted photo ${photoId}.`);
    return this.list(userId);
  }

  /**
   * Reorders the user's photos. The provided id set must be exactly the user's
   * current photos — no missing, extra, or foreign ids — so ordering can't be
   * driven from a stale or malicious partial set.
   */
  async reorder(userId: string, photoIds: string[]): Promise<PhotoEntity[]> {
    const current = await this.photoRepository.findAllForUser(userId);
    const currentIds = new Set(current.map((p) => p.id));
    const givenIds = new Set(photoIds);

    if (
      photoIds.length !== current.length ||
      givenIds.size !== photoIds.length ||
      ![...givenIds].every((id) => currentIds.has(id))
    ) {
      throw new BadRequestException(
        'photoIds must contain exactly your current photos, with no duplicates.',
      );
    }

    await this.photoRepository.applyOrder(photoIds);
    this.logger.log(`User ${userId} reordered ${photoIds.length} photos.`);
    return this.list(userId);
  }

  /** Sets the primary/display photo (unsets any previous primary). */
  async setPrimary(userId: string, photoId: string): Promise<PhotoEntity[]> {
    const existing = await this.photoRepository.findByIdForUser(
      photoId,
      userId,
    );
    if (!existing) {
      throw new NotFoundException('Photo not found.');
    }
    await this.photoRepository.setPrimary(userId, photoId);
    this.logger.log(`User ${userId} set photo ${photoId} as primary.`);
    return this.list(userId);
  }

  /**
   * Removes every photo (DB + S3) for a user — call from an account/profile
   * deletion flow so storage objects don't outlive the account. Safe to call
   * when the user has no photos.
   */
  async deleteAllForUser(userId: string): Promise<void> {
    const keys = await this.photoRepository.deleteAllForUser(userId);
    await this.s3.deleteObjects(keys);
    if (keys.length > 0) {
      this.logger.log(`Deleted ${keys.length} photos for user ${userId}.`);
    }
  }

  private buildKey(userId: string, mimetype: string): string {
    const ext = extensionForMime(mimetype);
    return `${StoragePrefix.profilePhotos}/${userId}/${randomUUID()}.${ext}`;
  }

  private async attachPresignedUrl(photo: PhotoEntity): Promise<PhotoEntity> {
    photo.cdnUrl = await this.s3.getPresignedGetUrl(photo.s3Key);
    return photo;
  }

  private async withPresignedUrls(
    photos: PhotoEntity[],
  ): Promise<PhotoEntity[]> {
    return Promise.all(photos.map((p) => this.attachPresignedUrl(p)));
  }
}
