import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

/** Body for `PATCH /chat/messages/:id` — the new text for a text message. The
 *  service additionally enforces sender-only, text-only, and the edit window. */
export class EditMessageDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(4000)
  content!: string;
}
