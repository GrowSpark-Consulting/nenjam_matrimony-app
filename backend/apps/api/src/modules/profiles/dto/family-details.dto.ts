import { Type } from 'class-transformer';
import {
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Min,
  ValidateNested,
} from 'class-validator';

// Mirrors ...profile_draft.dart -> FamilyMember (step 8, Father/Mother)
export class FamilyMemberDto {
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  age?: number;

  @IsOptional()
  @IsString()
  occupation?: string;
}

// Mirrors ...profile_draft.dart -> SiblingMember (step 8, dynamic Brothers/Sisters list)
export class SiblingMemberDto extends FamilyMemberDto {
  @IsOptional()
  @IsIn(['BROTHER', 'SISTER'])
  relation?: 'BROTHER' | 'SISTER';
}

// Mirrors ...profile_draft.dart -> FamilyDetails (step 8). Replaces the old
// flat fatherName/fatherOccupation/motherName/motherOccupation/brothers/
// sisters shape with structured per-person records — see profile.service.ts's
// writeProfileFromDraft() for how this maps onto UserProfile's
// fatherName/fatherAge/fatherOccupation/motherName/motherAge/
// motherOccupation/siblingDetails/siblings columns.
export class FamilyDetailsDto {
  @IsOptional()
  @ValidateNested()
  @Type(() => FamilyMemberDto)
  father?: FamilyMemberDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => FamilyMemberDto)
  mother?: FamilyMemberDto;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SiblingMemberDto)
  siblings?: SiblingMemberDto[];

  @IsOptional()
  @IsString()
  familyType?: string;

  @IsOptional()
  @IsString()
  familyValues?: string;

  @IsOptional()
  @IsString()
  familyStatus?: string;
}
