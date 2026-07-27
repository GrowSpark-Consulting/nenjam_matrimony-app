import {
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export const CHAT_MESSAGE_TYPES = ['TEXT', 'IMAGE', 'AUDIO', 'VIDEO'] as const;
export type ChatMessageTypeWire = (typeof CHAT_MESSAGE_TYPES)[number];

/** Body for POST /chat/messages. `content` is optional at the DTO level (a
 *  media message can have an empty caption); MessagesService enforces the real
 *  rules — TEXT needs non-empty content, media needs a `mediaUrl`. */
export class SendMessageDto {
  @IsString()
  @IsNotEmpty()
  roomId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  content?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  clientMessageId?: string;

  @IsOptional()
  @IsIn(CHAT_MESSAGE_TYPES)
  type?: ChatMessageTypeWire;

  @IsOptional()
  @IsString()
  @MaxLength(512)
  mediaUrl?: string;
}
