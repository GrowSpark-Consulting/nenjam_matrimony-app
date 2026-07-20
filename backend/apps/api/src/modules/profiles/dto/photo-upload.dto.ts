import { Transform } from 'class-transformer';
import { IsBoolean, IsOptional } from 'class-validator';

// Non-file fields that accompany a multipart photo upload. The binary is
// handled by @UploadedFile()/PhotoFilePipe, not here. `isPrimary` arrives as
// a form-field string ("true"/"false"), so it's coerced to a real boolean.
export class PhotoUploadDto {
  @IsOptional()
  @Transform(({ value }) =>
    typeof value === 'string' ? value.toLowerCase() === 'true' : value,
  )
  @IsBoolean()
  isPrimary?: boolean;
}
