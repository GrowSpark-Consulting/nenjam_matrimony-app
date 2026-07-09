import { IsArray, IsOptional, IsString } from 'class-validator';

// Mirrors ...profile_draft.dart -> LifestyleDetails (step 7)
export class LifestyleDetailsDto {
  @IsOptional()
  @IsString()
  eatingHabit?: string;

  @IsOptional()
  @IsString()
  smoking?: string;

  @IsOptional()
  @IsString()
  drinking?: string;

  @IsOptional()
  @IsString()
  fitness?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  hobbies?: string[];

  @IsOptional()
  @IsString()
  aboutMe?: string;
}
