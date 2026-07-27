/** POST /chat/attachments response. `mediaUrl` is the stored object key (which
 *  the client echoes back on POST /chat/messages); reads always return a
 *  short-lived presigned URL, never this raw key. */
export interface AttachmentUploadResponseDto {
  mediaUrl: string;
  contentType: string;
  size: number;
}
