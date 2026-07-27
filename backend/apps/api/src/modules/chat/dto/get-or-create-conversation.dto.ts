import { IsNotEmpty, IsString } from 'class-validator';

/** Body for POST /chat/conversations/get-or-create — the peer to open a thread
 *  with. The caller is always derived from the auth token, never the body. */
export class GetOrCreateConversationDto {
  @IsString()
  @IsNotEmpty()
  peerId!: string;
}
