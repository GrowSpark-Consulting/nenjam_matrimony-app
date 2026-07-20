import { ArrayNotEmpty, IsArray, IsUUID } from 'class-validator';

// Full ordered list of the caller's photo IDs; index becomes the new `order`.
// Must contain exactly the user's current photos (validated in PhotoService)
// so ordering can't be set from a partial or foreign set of IDs.
export class ReorderPhotosDto {
  @IsArray()
  @ArrayNotEmpty()
  @IsUUID('4', { each: true })
  photoIds!: string[];
}
