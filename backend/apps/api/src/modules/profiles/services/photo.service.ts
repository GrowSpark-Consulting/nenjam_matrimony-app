import { BadRequestException, Injectable } from '@nestjs/common';
import { PhotoRepository } from '../repositories/photo.repository';
import { PhotoEntity } from '../entities/photo.entity';
import { PhotoUploadDto } from '../dto/photo-upload.dto';

const MAX_PHOTOS_PER_USER = 6;

@Injectable()
export class PhotoService {
  constructor(private readonly photoRepository: PhotoRepository) {}

  async list(userId: string): Promise<PhotoEntity[]> {
    return this.photoRepository.findAllForUser(userId);
  }

  // Registers a photo already uploaded to S3 (see libs/storage — the actual
  // presigned-upload endpoint isn't wired yet, so the client is assumed to
  // have obtained s3Key/cdnUrl some other way for now). New rows start
  // unapproved; PhotoModerationProcessor (apps/worker) flips isApproved.
  async register(userId: string, dto: PhotoUploadDto): Promise<PhotoEntity> {
    const existingCount = await this.photoRepository.countForUser(userId);
    if (existingCount >= MAX_PHOTOS_PER_USER) {
      throw new BadRequestException(
        `Cannot upload more than ${MAX_PHOTOS_PER_USER} photos.`,
      );
    }

    return this.photoRepository.create(userId, {
      s3Key: dto.s3Key,
      cdnUrl: dto.cdnUrl,
      isPrimary: dto.isPrimary ?? existingCount === 0,
      order: existingCount,
    });
  }
}
