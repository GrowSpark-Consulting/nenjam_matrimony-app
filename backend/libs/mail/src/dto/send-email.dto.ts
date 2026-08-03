import {
  IsEmail,
  IsEnum,
  IsObject,
  IsOptional,
  IsUUID,
  MaxLength,
} from 'class-validator';
import { EmailType } from '../types/email-type.enum';
import type { EmailPayload } from '../interfaces/email.interface';

/**
 * Input contract for enqueuing an email.
 *
 * Validated rather than trusted even though most callers are internal: a bad
 * recipient that slips through becomes a job that fails 5 times, backs off for
 * ~2.5 minutes and lands in the DLQ. Rejecting it synchronously at the call
 * site turns a delayed, invisible failure into an immediate, attributable one.
 */
export class SendEmailDto {
  @IsEnum(EmailType)
  emailType!: EmailType;

  /**
   * `class-validator`'s IsEmail is the same validator Resend applies server
   * side, so anything accepted here is accepted by the provider.
   * 320 chars is the RFC 5321 maximum (64 local + @ + 255 domain).
   */
  @IsEmail({}, { message: 'to must be a valid email address' })
  @MaxLength(320)
  to!: string;

  /** Template variables. Escaped at render time — see TemplateRenderer.render. */
  @IsObject()
  @IsOptional()
  payload?: EmailPayload;

  /** Links the EmailLog row to a user. Omitted for pre-signup mail. */
  @IsUUID()
  @IsOptional()
  userId?: string;
}
