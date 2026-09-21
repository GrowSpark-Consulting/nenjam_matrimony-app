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
import type { GetObjectCommandOutput } from '@aws-sdk/client-s3';
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

/** Formats [S3Service.getObjectBytes] can recognise. "jpeg" covers .jpg too. */
export type StoredObjectFormat = 'jpeg' | 'png' | 'pdf';

/** Default read ceiling — also Rekognition's limit for inline image bytes. */
export const MAX_OBJECT_READ_BYTES = 5 * 1024 * 1024;

export interface GetObjectBytesOptions {
  /** Reject objects larger than this, before downloading the body. */
  maxBytes?: number;
  /** Formats the caller accepts, judged by the object's leading bytes. */
  allowedFormats?: readonly StoredObjectFormat[];
}

/**
 * Outcome of a bounded object read. Rejections are values, not exceptions, so
 * callers map them onto their own domain errors; only an unexpected storage
 * failure throws.
 */
export type GetObjectBytesResult =
  | {
      ok: true;
      bytes: Uint8Array;
      format: StoredObjectFormat;
      contentLength: number;
    }
  | {
      ok: false;
      reason: 'NOT_FOUND' | 'TOO_LARGE' | 'EMPTY' | 'UNSUPPORTED_FORMAT';
    };

/**
 * Identifies an object's real format from its magic bytes. Deliberately not
 * trusting the stored Content-Type: that is whatever the uploading client
 * declared, so a WebP (or anything else) labelled image/jpeg is still caught.
 */
export function detectObjectFormat(
  bytes: Uint8Array,
): StoredObjectFormat | null {
  const startsWith = (sig: number[]) =>
    bytes.length >= sig.length && sig.every((b, i) => bytes[i] === b);

  if (startsWith([0xff, 0xd8, 0xff])) return 'jpeg';
  if (startsWith([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'png';
  }
  if (startsWith([0x25, 0x50, 0x44, 0x46, 0x2d])) return 'pdf'; // "%PDF-"
  return null;
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
   * Reads an object's bytes server-side — read-only, bounded, and format
   * checked. Used where the backend itself must hand the image to another
   * service (face verification sends the profile photo to Rekognition
   * CompareFaces), never to proxy files to clients.
   *
   * The size check runs on the response's ContentLength BEFORE the body is
   * consumed, so an oversized object is never pulled into memory; the stream
   * is destroyed instead. Uses the same client/credentials as every other
   * method here, which already read these objects to presign them.
   */
  async getObjectBytes(
    key: string,
    options: GetObjectBytesOptions = {},
  ): Promise<GetObjectBytesResult> {
    const { client, bucket } = this.ensure();
    const maxBytes = options.maxBytes ?? MAX_OBJECT_READ_BYTES;
    const allowed = options.allowedFormats ?? ['jpeg', 'png', 'pdf'];

    let response: GetObjectCommandOutput;
    try {
      response = await client.send(
        new GetObjectCommand({ Bucket: bucket, Key: key }),
      );
    } catch (error) {
      const name = (error as { name?: string }).name;
      const status = (error as { $metadata?: { httpStatusCode?: number } })
        .$metadata?.httpStatusCode;
      if (name === 'NoSuchKey' || name === 'NotFound' || status === 404) {
        return { ok: false, reason: 'NOT_FOUND' };
      }
      this.logger.error(
        `Failed to read s3://${bucket}/${key}: ${(error as Error).message}`,
      );
      throw new InternalServerErrorException('Failed to read the file.');
    }

    const body = response.Body;
    const contentLength = response.ContentLength;
    if (
      contentLength == null ||
      !Number.isFinite(contentLength) ||
      contentLength > maxBytes
    ) {
      discardBody(body);
      return { ok: false, reason: 'TOO_LARGE' };
    }
    if (contentLength === 0 || !body) {
      discardBody(body);
      return { ok: false, reason: 'EMPTY' };
    }

    const bytes = await body.transformToByteArray();
    // Defensive: never trust ContentLength alone for the ceiling.
    if (bytes.length > maxBytes) return { ok: false, reason: 'TOO_LARGE' };
    if (bytes.length === 0) return { ok: false, reason: 'EMPTY' };

    const format = detectObjectFormat(bytes);
    if (!format || !allowed.includes(format)) {
      return { ok: false, reason: 'UNSUPPORTED_FORMAT' };
    }
    return { ok: true, bytes, format, contentLength: bytes.length };
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

/**
 * Releases an unread GetObject body. In Node the body is a Readable socket
 * stream; leaving it unconsumed would hold the HTTP connection open until the
 * pool times it out.
 */
function discardBody(body: unknown): void {
  const stream = body as { destroy?: () => void } | undefined;
  stream?.destroy?.();
}
