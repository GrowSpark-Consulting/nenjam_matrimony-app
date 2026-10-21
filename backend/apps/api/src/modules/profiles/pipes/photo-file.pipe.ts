import { BadRequestException, Injectable, PipeTransform } from '@nestjs/common';
import { sniffImageMime } from '@app/common';

/** A multer file, kept local so this pipe doesn't depend on Express types. */
export interface UploadedImageFile {
  originalname: string;
  mimetype: string;
  size: number;
  buffer: Buffer;
}

export const ALLOWED_IMAGE_MIME_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
] as const;

export const MAX_PHOTO_BYTES = 5 * 1024 * 1024; // 5 MB

const EXTENSION_BY_MIME: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

export function extensionForMime(mime: string): string {
  return EXTENSION_BY_MIME[mime] ?? 'bin';
}

/**
 * Validates an uploaded profile photo: presence, MIME allow-list, and size
 * cap. Rejects with a 400 carrying an actionable message rather than letting
 * a bad file reach S3. Runs on the `@UploadedFile()` param.
 */
@Injectable()
export class PhotoFilePipe implements PipeTransform<
  UploadedImageFile | undefined,
  UploadedImageFile
> {
  transform(file: UploadedImageFile | undefined): UploadedImageFile {
    if (!file) {
      throw new BadRequestException(
        'No file was uploaded (field name "file").',
      );
    }
    if (!ALLOWED_IMAGE_MIME_TYPES.includes(file.mimetype as never)) {
      throw new BadRequestException(
        `Unsupported image type "${file.mimetype}". Allowed: ${ALLOWED_IMAGE_MIME_TYPES.join(', ')}.`,
      );
    }
    if (file.size > MAX_PHOTO_BYTES) {
      throw new BadRequestException(
        `Image is too large (${(file.size / 1024 / 1024).toFixed(1)} MB). Max ${MAX_PHOTO_BYTES / 1024 / 1024} MB.`,
      );
    }
    if (!file.buffer || file.buffer.length === 0) {
      throw new BadRequestException('Uploaded file is empty.');
    }
    // The declared type is client-chosen, so the bytes decide: a file whose
    // content is not an allowed image is refused, and one whose content is an
    // allowed image is stored under its real type even if it was mislabelled.
    const actual = sniffImageMime(file.buffer);
    if (!actual || !ALLOWED_IMAGE_MIME_TYPES.includes(actual as never)) {
      throw new BadRequestException(
        `The file is not a valid image. Allowed: ${ALLOWED_IMAGE_MIME_TYPES.join(', ')}.`,
      );
    }
    return actual === file.mimetype ? file : { ...file, mimetype: actual };
  }
}
