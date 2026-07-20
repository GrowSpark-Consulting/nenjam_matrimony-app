import {
  Injectable,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import {
  DeleteObjectCommand,
  DeleteObjectsCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { AppConfigService } from '@app/config';

/** Object-key prefixes — one folder per asset class inside the bucket. */
export const StoragePrefix = {
  profilePhotos: 'profile-photos',
  verificationDocs: 'verification-docs',
} as const;

export interface UploadObjectParams {
  key: string;
  body: Buffer;
  contentType: string;
}

/**
 * Thin wrapper over the AWS S3 v3 client for the app's private bucket.
 *
 * The bucket is treated as private: objects are never public-read, so reads
 * always go through a short-lived presigned GET URL ([getPresignedGetUrl]).
 * Credentials come exclusively from the environment via AppConfigService —
 * nothing is hardcoded. If the S3 env vars are absent the service still
 * constructs (so the app boots), but any operation throws a clear 500 rather
 * than failing obscurely deep inside the SDK.
 */
@Injectable()
export class S3Service {
  private readonly logger = new Logger(S3Service.name);
  private readonly client: S3Client | null;
  private readonly bucket?: string;

  constructor(private readonly config: AppConfigService) {
    const { region, accessKeyId, secretAccessKey, bucket } =
      this.config.storage;
    this.bucket = bucket;

    if (region && accessKeyId && secretAccessKey && bucket) {
      this.client = new S3Client({
        region,
        credentials: { accessKeyId, secretAccessKey },
      });
      this.logger.log(
        `S3Service initialized (bucket="${bucket}", region="${region}").`,
      );
    } else {
      this.client = null;
      this.logger.warn(
        'S3Service not configured (AWS_REGION / AWS_ACCESS_KEY_ID / ' +
          'AWS_SECRET_ACCESS_KEY / AWS_S3_BUCKET_NAME missing) — photo ' +
          'upload endpoints will return 500 until these are set.',
      );
    }
  }

  isConfigured(): boolean {
    return this.client !== null;
  }

  /**
   * Durable virtual-hosted object URL for record-keeping in the DB. Not
   * directly fetchable while the bucket is private — clients always receive a
   * presigned URL from [getPresignedGetUrl] instead — but it's the stable,
   * non-expiring reference to the object.
   */
  getObjectUrl(key: string): string {
    const { bucket } = this.ensure();
    const region = this.config.storage.region;
    return `https://${bucket}.s3.${region}.amazonaws.com/${key}`;
  }

  private ensure(): { client: S3Client; bucket: string } {
    if (!this.client || !this.bucket) {
      throw new InternalServerErrorException(
        'File storage is not configured on this server.',
      );
    }
    return { client: this.client, bucket: this.bucket };
  }

  /** Uploads a single object. Throws on failure — the caller owns rollback. */
  async uploadObject({ key, body, contentType }: UploadObjectParams): Promise<void> {
    const { client, bucket } = this.ensure();
    try {
      await client.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key: key,
          Body: body,
          ContentType: contentType,
        }),
      );
      this.logger.log(`Uploaded s3://${bucket}/${key} (${body.length} bytes).`);
    } catch (error) {
      this.logger.error(
        `Failed to upload s3://${bucket}/${key}: ${(error as Error).message}`,
      );
      throw new InternalServerErrorException('Failed to store the file.');
    }
  }

  /**
   * Deletes one object. Best-effort: logs and swallows failures so a storage
   * hiccup during cleanup never surfaces as a request error after the DB row
   * is already gone (S3 DELETE is idempotent — a missing key is a success).
   */
  async deleteObject(key: string): Promise<void> {
    const { client, bucket } = this.ensure();
    try {
      await client.send(
        new DeleteObjectCommand({ Bucket: bucket, Key: key }),
      );
      this.logger.log(`Deleted s3://${bucket}/${key}.`);
    } catch (error) {
      this.logger.error(
        `Failed to delete s3://${bucket}/${key}: ${(error as Error).message}`,
      );
    }
  }

  /** Bulk delete (e.g. removing every photo when an account is deleted). */
  async deleteObjects(keys: string[]): Promise<void> {
    if (keys.length === 0) return;
    const { client, bucket } = this.ensure();
    try {
      await client.send(
        new DeleteObjectsCommand({
          Bucket: bucket,
          Delete: { Objects: keys.map((Key) => ({ Key })) },
        }),
      );
      this.logger.log(`Deleted ${keys.length} objects from s3://${bucket}.`);
    } catch (error) {
      this.logger.error(
        `Failed bulk delete of ${keys.length} objects: ${(error as Error).message}`,
      );
    }
  }

  /**
   * Short-lived presigned GET URL so a private object can be displayed by the
   * client without exposing credentials or making the bucket public.
   * Default TTL 1h — long enough for a screen's lifetime, short enough that a
   * leaked URL expires quickly.
   */
  async getPresignedGetUrl(key: string, expiresIn = 3600): Promise<string> {
    const { client, bucket } = this.ensure();
    return getSignedUrl(
      client,
      new GetObjectCommand({ Bucket: bucket, Key: key }),
      { expiresIn },
    );
  }
}
