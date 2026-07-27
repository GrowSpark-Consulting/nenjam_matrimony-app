import {
  BadRequestException,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { S3Service } from '@app/storage';
import {
  ChatAttachmentScanner,
  UploadedAttachmentFile,
} from './chat-attachment-scanner';
import { AttachmentUploadResponseDto } from '../dto/attachment.response.dto';

type AttachmentKind = 'IMAGE' | 'AUDIO';

// Allow-lists + caps enforced SERVER-SIDE — client checks are UX only and never
// trusted. Audio: the Flutter client records AAC-LC in an MP4 container (.m4a),
// reported as one of these depending on platform.
const MIME_BY_KIND: Record<AttachmentKind, readonly string[]> = {
  IMAGE: ['image/jpeg', 'image/png', 'image/webp', 'image/heic'],
  AUDIO: ['audio/mp4', 'audio/aac', 'audio/m4a', 'audio/x-m4a'],
};
const MAX_BYTES_BY_KIND: Record<AttachmentKind, number> = {
  IMAGE: 8 * 1024 * 1024, // 8 MB
  AUDIO: 12 * 1024 * 1024, // 12 MB (~a couple minutes of AAC)
};
const EXTENSION_BY_MIME: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'audio/mp4': 'm4a',
  'audio/aac': 'aac',
  'audio/m4a': 'm4a',
  'audio/x-m4a': 'm4a',
};

/**
 * Chat attachment upload. Validates type/MIME/size, runs the virus-scan seam,
 * stores the bytes in the object store (private bucket), and returns the object
 * KEY as `mediaUrl` — reads presign it into a short-lived URL, so media is never
 * a permanent public link. Storage is behind [S3Service] (S3 / R2 / MinIO), so
 * the storage backend can change with no change here.
 */
@Injectable()
export class AttachmentsService {
  constructor(
    private readonly s3: S3Service,
    private readonly scanner: ChatAttachmentScanner,
  ) {}

  async upload(
    userId: string,
    file: UploadedAttachmentFile | undefined,
    rawType: string | undefined,
  ): Promise<AttachmentUploadResponseDto> {
    const kind = this.parseKind(rawType);
    if (!file) throw new BadRequestException('No file was uploaded.');

    if (!MIME_BY_KIND[kind].includes(file.mimetype)) {
      throw new BadRequestException(
        `Unsupported ${kind.toLowerCase()} type: ${file.mimetype}.`,
      );
    }
    if (file.size <= 0) {
      throw new BadRequestException('Uploaded file is empty.');
    }
    if (file.size > MAX_BYTES_BY_KIND[kind]) {
      throw new BadRequestException(
        `${kind === 'AUDIO' ? 'Voice message' : 'Image'} is too large.`,
      );
    }

    await this.scanner.assertClean(file);

    if (!this.s3.isConfigured()) {
      throw new ServiceUnavailableException(
        'Attachment storage is not available.',
      );
    }

    const ext = EXTENSION_BY_MIME[file.mimetype] ?? 'bin';
    const key = `chat-media/${userId}/${randomUUID()}.${ext}`;
    await this.s3.uploadObject({
      key,
      body: file.buffer,
      contentType: file.mimetype,
    });

    return { mediaUrl: key, contentType: file.mimetype, size: file.size };
  }

  private parseKind(rawType: string | undefined): AttachmentKind {
    const kind = (rawType ?? '').toUpperCase();
    if (kind === 'IMAGE' || kind === 'AUDIO') return kind;
    throw new BadRequestException('type must be IMAGE or AUDIO.');
  }
}
