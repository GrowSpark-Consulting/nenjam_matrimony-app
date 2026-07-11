import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type { ProfilePhoto } from '../../../../../../libs/database/generated/client';
import { PhotoEntity } from '../entities/photo.entity';

@Injectable()
export class PhotoRepository {
  constructor(private readonly prisma: PrismaService) {}

  async findAllForUser(userId: string): Promise<PhotoEntity[]> {
    const rows = await this.prisma.profilePhoto.findMany({
      where: { userId },
      orderBy: { order: 'asc' },
    });
    return rows.map((row) => this.toEntity(row));
  }

  async create(
    userId: string,
    data: { s3Key: string; cdnUrl: string; isPrimary: boolean; order: number },
  ): Promise<PhotoEntity> {
    if (data.isPrimary) {
      await this.prisma.profilePhoto.updateMany({
        where: { userId, isPrimary: true },
        data: { isPrimary: false },
      });
    }
    const row = await this.prisma.profilePhoto.create({
      data: { userId, ...data },
    });
    return this.toEntity(row);
  }

  async countForUser(userId: string): Promise<number> {
    return this.prisma.profilePhoto.count({ where: { userId } });
  }

  private toEntity(row: ProfilePhoto): PhotoEntity {
    const entity = new PhotoEntity();
    Object.assign(entity, row);
    return entity;
  }
}
