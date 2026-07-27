import { IsNotEmpty, IsOptional, IsString } from 'class-validator';
import { PaginationQueryDto } from '@app/common';

/** Query for GET /chat/messages — the room plus page/limit. Extends the shared
 *  pagination DTO so `conversationId` is whitelisted alongside page/limit (the
 *  global forbidNonWhitelisted pipe would otherwise 400 the extra param).
 *
 *  `cursor` is optional and backward-compatible: when present the endpoint uses
 *  keyset pagination (the page returned is strictly older than the message with
 *  this id — stable under concurrent inserts), and when absent it falls back to
 *  the original `?page=&limit=` offset paging. An empty `cursor=` means "first
 *  keyset page" (newest). */
export class MessageListQueryDto extends PaginationQueryDto {
  @IsString()
  @IsNotEmpty()
  conversationId!: string;

  @IsOptional()
  @IsString()
  cursor?: string;
}
