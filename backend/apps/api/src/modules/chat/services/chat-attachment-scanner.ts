import { Injectable, Logger } from '@nestjs/common';

/** A chat attachment as multer hands it to us. Kept local so this file doesn't
 *  depend on Express types. */
export interface UploadedAttachmentFile {
  originalname: string;
  mimetype: string;
  size: number;
  buffer: Buffer;
}

/**
 * Virus/malware scan seam. The default is a pass-through (no external scanner
 * wired), but it's a real DI boundary: a production deployment binds a
 * ClamAV / VirusTotal / cloud-scanner implementation to this token and every
 * chat upload flows through it before it's stored — no call-site change.
 *
 * `assertClean` MUST throw (a BadRequest/UnprocessableEntity) on an infected or
 * unscannable file; returning normally means "safe to store".
 */
@Injectable()
export class ChatAttachmentScanner {
  private readonly logger = new Logger(ChatAttachmentScanner.name);

  // eslint-disable-next-line @typescript-eslint/require-await
  async assertClean(file: UploadedAttachmentFile): Promise<void> {
    // No scanner configured — pass through. Logged at debug so it's visible
    // that uploads are currently unscanned in this deployment.
    this.logger.debug(
      `Attachment scan skipped (no scanner bound): ${file.originalname} ${file.size}B`,
    );
  }
}
