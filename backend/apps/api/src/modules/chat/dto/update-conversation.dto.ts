import { IsBoolean, IsOptional } from 'class-validator';

/**
 * Per-user conversation flags a caller may toggle via `PATCH
 * /chat/conversations/:id`. Every field is optional — only the flags present in
 * the body are changed; the rest keep their current value. These are the
 * frontend's field names (`pinned`/`muted`/`archived`), mapped to the
 * `ChatParticipantState` columns in the service.
 */
export class UpdateConversationDto {
  @IsOptional()
  @IsBoolean()
  pinned?: boolean;

  @IsOptional()
  @IsBoolean()
  muted?: boolean;

  @IsOptional()
  @IsBoolean()
  archived?: boolean;
}
