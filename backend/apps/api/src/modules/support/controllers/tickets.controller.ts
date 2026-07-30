import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { TicketsService } from '../services/tickets.service';
import { CreateTicketDto } from '../dto/create-ticket.dto';
import {
  SupportTicketListResponseDto,
  SupportTicketResponseDto,
} from '../dto/support-ticket.response.dto';

// Support tickets. Every route derives the user from the verified Firebase
// token (`@CurrentUser('id')`), so a caller can only create tickets as — and
// list tickets belonging to — themselves. No business logic here.
@Controller('support/tickets')
@UseGuards(FirebaseAuthGuard)
export class TicketsController {
  constructor(private readonly ticketsService: TicketsService) {}

  /** POST /support/tickets — submit a Contact/Bug/Feature/Feedback ticket. */
  @Post()
  create(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateTicketDto,
  ): Promise<SupportTicketResponseDto> {
    return this.ticketsService.createTicket(userId, dto);
  }

  /** GET /support/tickets — the caller's ticket history, newest first. */
  @Get()
  list(
    @CurrentUser('id') userId: string,
  ): Promise<SupportTicketListResponseDto> {
    return this.ticketsService.getMyTickets(userId);
  }
}
