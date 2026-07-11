import { IsBoolean, IsOptional, IsString } from 'class-validator';

// Mirrors ...profile_draft.dart -> HoroscopeDetails (step 9).
// Field names deliberately match the Flutter form, not the Prisma
// AstrologyProfile columns (rasi/dosham enum) — that mapping happens in
// ProfileService.finalize().
export class HoroscopeDetailsDto {
  @IsOptional()
  @IsString()
  birthTime?: string;

  @IsOptional()
  @IsString()
  birthPlace?: string;

  @IsOptional()
  @IsString()
  rashi?: string;

  @IsOptional()
  @IsString()
  nakshatra?: string;

  @IsOptional()
  @IsString()
  star?: string;

  @IsOptional()
  @IsString()
  manglik?: string;

  @IsOptional()
  @IsString()
  dosham?: string;

  @IsOptional()
  @IsBoolean()
  horoscopeAvailable?: boolean;
}
