import {
  Body,
  Controller,
  Post,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { AttachmentsService } from '../services/attachments.service';
import type { UploadedAttachmentFile } from '../services/chat-attachment-scanner';
import { AttachmentUploadResponseDto } from '../dto/attachment.response.dto';

// A generous 20 MB multer hard cap guards against pathological memory use;
// per-kind product limits (8 MB image / 12 MB audio) + MIME allow-lists are
// enforced by AttachmentsService with a friendly 400. Files stream through
// memory, never touching disk.
const fileInterceptor = FileInterceptor('file', {
  storage: memoryStorage(),
  limits: { fileSize: 20 * 1024 * 1024, files: 1 },
});

@Controller('chat/attachments')
@UseGuards(FirebaseAuthGuard)
export class AttachmentsController {
  constructor(private readonly attachmentsService: AttachmentsService) {}

  /** POST /chat/attachments (multipart: `file`, `type`=IMAGE|AUDIO) — stores the
   *  file and returns its object key as `mediaUrl` for a follow-up
   *  POST /chat/messages. The message send is where chat-eligibility is enforced. */
  @Post()
  @UseInterceptors(fileInterceptor)
  upload(
    @CurrentUser('id') userId: string,
    @UploadedFile() file: UploadedAttachmentFile | undefined,
    @Body('type') type: string,
  ): Promise<AttachmentUploadResponseDto> {
    return this.attachmentsService.upload(userId, file, type);
  }
}
