import { IsBoolean, IsOptional, IsString } from 'class-validator';

// Registers a photo already uploaded to S3 (see libs/storage — presigned-URL
// upload isn't wired yet, so this assumes the client has the resulting key).
// Mirrors ...profile_draft.dart -> PhotoGallery (step 11) at the per-photo level.
export class PhotoUploadDto {
  @IsString()
  s3Key!: string;

  @IsString()
  cdnUrl!: string;

  @IsOptional()
  @IsBoolean()
  isPrimary?: boolean;
}
