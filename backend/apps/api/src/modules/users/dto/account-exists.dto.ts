import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsOptional, IsString, Matches } from 'class-validator';

/** Identifiers a signup screen wants to check before creating an account. */
export class AccountExistsRequestDto {
  @ApiPropertyOptional({ example: 'someone@example.com' })
  @IsOptional()
  @IsEmail({}, { message: 'email must be a valid address' })
  email?: string;

  /** E.164, the same representation the mobile app stores. */
  @ApiPropertyOptional({ example: '+919876543210' })
  @IsOptional()
  @IsString()
  @Matches(/^\+[1-9]\d{7,14}$/, {
    message: 'phone must be in E.164 format, e.g. +919876543210',
  })
  phone?: string;
}

/**
 * Deliberately booleans and nothing else. This endpoint is unauthenticated,
 * so it must never leak a uid, a name, or which provider an account uses.
 */
export class AccountExistsResponseDto {
  @ApiProperty()
  emailExists!: boolean;

  @ApiProperty()
  phoneExists!: boolean;
}
