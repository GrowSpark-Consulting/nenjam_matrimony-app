// Mapped from Prisma's ProfilePhoto row by PhotoRepository.
export class PhotoEntity {
  id!: string;
  userId!: string;
  s3Key!: string;
  cdnUrl!: string;
  isPrimary!: boolean;
  order!: number;
  isApproved!: boolean;
}
