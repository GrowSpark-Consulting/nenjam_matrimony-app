import { IsNotEmpty, IsString } from 'class-validator';
import { PaginationQueryDto } from '@app/common';

/** Query for GET /chat/messages — the room plus page/limit. Extends the shared
 *  pagination DTO so `conversationId` is whitelisted alongside page/limit (the
 *  global forbidNonWhitelisted pipe would otherwise 400 the extra param). */
export class MessageListQueryDto extends PaginationQueryDto {
  @IsString()
  @IsNotEmpty()
  conversationId!: string;
}
