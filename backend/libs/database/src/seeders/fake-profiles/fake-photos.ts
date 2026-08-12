/**
 * Uploads the 30 demo photos and creates their ProfilePhoto rows.
 *
 * The photos live in the repository at `photos/profile_NN.jpg` (committed in
 * e935757) and are NOT in object storage — the bucket only held real
 * `chat-media/` and `profile-photos/` objects from actual app usage. So this
 * uploads them, rather than pointing rows at objects that don't exist.
 *
 * Key convention deliberately mirrors PhotoService.buildKey():
 *
 *     profile-photos/{userId}/{name}.{ext}
 *
 * with one difference — where the real service uses randomUUID() for the file
 * name, this uses a fixed `seed-NN`. A random name would upload 30 new objects
 * on every run and orphan the previous ones; a deterministic one makes the
 * upload idempotent and lets `unseed` find exactly what it wrote.
 *
 * `cdnUrl` is stored as the durable virtual-hosted URL, matching
 * S3Service.getObjectUrl(). The application overwrites it with a short-lived
 * presigned URL at read time (PhotoService.attachPresignedUrl), so this column
 * is a stable reference, never what the client actually fetches.
 */
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import {
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';

export interface PhotoUploadResult {
  index: number;
  userId: string;
  s3Key: string;
  cdnUrl: string;
  bytes: number;
  /** False when the object was already in the bucket from a previous run. */
  uploaded: boolean;
}

export interface PhotoStorageConfig {
  region: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
  /** Absolute path to the repository's `photos/` directory. */
  photosDir: string;
}

export function readStorageConfig(photosDir: string): PhotoStorageConfig | null {
  const region = process.env.AWS_REGION;
  const bucket = process.env.AWS_S3_BUCKET_NAME;
  const accessKeyId = process.env.AWS_ACCESS_KEY_ID;
  const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY;
  if (!region || !bucket || !accessKeyId || !secretAccessKey) return null;
  return { region, bucket, accessKeyId, secretAccessKey, photosDir };
}

export function photoFileName(index: number): string {
  return `profile_${String(index).padStart(2, '0')}.jpg`;
}

export function photoObjectKey(userId: string, index: number): string {
  return `profile-photos/${userId}/seed-${String(index).padStart(2, '0')}.jpg`;
}

function objectUrl(cfg: PhotoStorageConfig, key: string): string {
  return `https://${cfg.bucket}.s3.${cfg.region}.amazonaws.com/${key}`;
}

function makeClient(cfg: PhotoStorageConfig): S3Client {
  return new S3Client({
    region: cfg.region,
    credentials: {
      accessKeyId: cfg.accessKeyId,
      secretAccessKey: cfg.secretAccessKey,
    },
  });
}

/** True when the object already exists, so a re-run doesn't re-upload it. */
async function exists(client: S3Client, bucket: string, key: string): Promise<boolean> {
  try {
    await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch (error) {
    const name = (error as { name?: string }).name;
    if (name === 'NotFound' || name === 'NoSuchKey') return false;
    throw error;
  }
}

/**
 * Uploads one member's photo if it isn't already there, and returns the
 * metadata needed for the ProfilePhoto row.
 */
export async function uploadFakePhoto(
  cfg: PhotoStorageConfig,
  client: S3Client,
  userId: string,
  index: number,
): Promise<PhotoUploadResult> {
  const key = photoObjectKey(userId, index);
  const body = await readFile(join(cfg.photosDir, photoFileName(index)));

  const already = await exists(client, cfg.bucket, key);
  if (!already) {
    await client.send(
      new PutObjectCommand({
        Bucket: cfg.bucket,
        Key: key,
        Body: body,
        ContentType: 'image/jpeg',
      }),
    );
  }

  return {
    index,
    userId,
    s3Key: key,
    cdnUrl: objectUrl(cfg, key),
    bytes: body.byteLength,
    uploaded: !already,
  };
}

export { makeClient as makeS3Client, exists as objectExists };
