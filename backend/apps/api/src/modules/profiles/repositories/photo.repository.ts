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

  /** Ownership-scoped fetch — returns null if the id isn't this user's. */
  async findByIdForUser(
    id: string,
    userId: string,
  ): Promise<PhotoEntity | null> {
    const row = await this.prisma.profilePhoto.findFirst({
      where: { id, userId },
    });
    return row ? this.toEntity(row) : null;
  }

  async countForUser(userId: string): Promise<number> {
    return this.prisma.profilePhoto.count({ where: { userId } });
  }

  async create(
    userId: string,
    data: { s3Key: string; cdnUrl: string; isPrimary: boolean; order: number },
  ): Promise<PhotoEntity> {
    const row = await this.prisma.$transaction(async (tx) => {
      if (data.isPrimary) {
        await tx.profilePhoto.updateMany({
          where: { userId, isPrimary: true },
          data: { isPrimary: false },
        });
      }
      return tx.profilePhoto.create({ data: { userId, ...data } });
    });
    return this.toEntity(row);
  }

  /** Replace the stored object of an existing (already ownership-checked) row. */
  async updateStorage(
    id: string,
    data: { s3Key: string; cdnUrl: string },
  ): Promise<PhotoEntity> {
    const row = await this.prisma.profilePhoto.update({
      where: { id },
      data,
    });
    return this.toEntity(row);
  }

  async deleteById(id: string): Promise<void> {
    await this.prisma.profilePhoto.delete({ where: { id } });
  }

  /**
   * Makes `id` the sole primary for `userId`, atomically. Assumes the caller
   * has already confirmed `id` belongs to `userId`.
   */
  async setPrimary(userId: string, id: string): Promise<void> {
    await this.prisma.$transaction([
      this.prisma.profilePhoto.updateMany({
        where: { userId, isPrimary: true },
        data: { isPrimary: false },
      }),
      this.prisma.profilePhoto.update({
        where: { id },
        data: { isPrimary: true },
      }),
    ]);
  }

  /** Promotes the lowest-order remaining photo to primary (post-delete). */
  async promoteFirstToPrimary(userId: string): Promise<void> {
    const next = await this.prisma.profilePhoto.findFirst({
      where: { userId },
      orderBy: { order: 'asc' },
    });
    if (next && !next.isPrimary) {
      await this.prisma.profilePhoto.update({
        where: { id: next.id },
        data: { isPrimary: true },
      });
    }
  }

  /** Applies `order` = index for each id, atomically. */
  async applyOrder(orderedIds: string[]): Promise<void> {
    await this.prisma.$transaction(
      orderedIds.map((id, index) =>
        this.prisma.profilePhoto.update({
          where: { id },
          data: { order: index },
        }),
      ),
    );
  }

  /** Removes every row for the user and returns their S3 keys for cleanup. */
  async deleteAllForUser(userId: string): Promise<string[]> {
    const rows = await this.prisma.profilePhoto.findMany({
      where: { userId },
      select: { s3Key: true },
    });
    await this.prisma.profilePhoto.deleteMany({ where: { userId } });
    return rows.map((r) => r.s3Key);
  }

  private toEntity(row: ProfilePhoto): PhotoEntity {
    const entity = new PhotoEntity();
    Object.assign(entity, row);
    return entity;
  }
}
