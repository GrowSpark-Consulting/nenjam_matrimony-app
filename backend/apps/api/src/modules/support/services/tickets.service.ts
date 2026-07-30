import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { TicketRepository } from '../repositories/ticket.repository';
import { CreateTicketDto } from '../dto/create-ticket.dto';
import {
  SupportTicketListResponseDto,
  SupportTicketResponseDto,
} from '../dto/support-ticket.response.dto';
import {
  ticketTypeToPrisma,
  toSupportTicketResponse,
} from '../mappers/support-ticket.mapper';

/**
 * Support ticket business logic. Owns validation, Prisma↔wire mapping, and the
 * response envelope; the controller only forwards the authenticated user id and
 * the DTO, and the repository only persists. Prisma models never leave this
 * layer — every method returns a wire DTO.
 */
@Injectable()
export class TicketsService {
  private readonly logger = new Logger(TicketsService.name);

  constructor(private readonly ticketRepository: TicketRepository) {}

  /** Creates a ticket for [userId]. Trims text and rejects whitespace-only
   *  input (defence-in-depth on top of the DTO's non-empty validation). */
  async createTicket(
    userId: string,
    dto: CreateTicketDto,
  ): Promise<SupportTicketResponseDto> {
    const subject = dto.subject.trim();
    const message = dto.message.trim();
    if (subject.length === 0 || message.length === 0) {
      throw new BadRequestException('Subject and message are required.');
    }

    const ticket = await this.ticketRepository.createTicket({
      userId,
      type: ticketTypeToPrisma(dto.type),
      subject,
      body: message,
    });
    this.logger.log(
      `Support ticket ${ticket.id} (${ticket.type}) created for user ${userId}.`,
    );
    return toSupportTicketResponse(ticket);
  }

  /** The caller's tickets, newest first, in the paginatable list envelope. */
  async getMyTickets(userId: string): Promise<SupportTicketListResponseDto> {
    const tickets = await this.ticketRepository.findTicketsByUser(userId);
    return { items: tickets.map(toSupportTicketResponse) };
  }
}
