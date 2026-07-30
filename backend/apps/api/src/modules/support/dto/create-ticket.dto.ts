import { IsEnum, IsNotEmpty, IsString, MaxLength } from 'class-validator';
import { SupportTicketTypeWire } from './support-ticket.response.dto';

/** Body for `POST /support/tickets`. `type` is the wire enum (mapped to the
 *  Prisma enum in the service); `message` maps to the DB `body` column. */
export class CreateTicketDto {
  @IsEnum(SupportTicketTypeWire)
  type!: SupportTicketTypeWire;

  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  subject!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(5000)
  message!: string;
}
