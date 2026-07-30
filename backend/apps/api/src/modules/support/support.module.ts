import { Module } from '@nestjs/common';
import { TicketsController } from './controllers/tickets.controller';
import { TicketsService } from './services/tickets.service';
import { TicketRepository } from './repositories/ticket.repository';

// PrismaService (@app/database) is provided by its @Global module, so nothing
// extra needs importing here. FAQ is intentionally not wired — that content is
// static on the client today (see the frontend/backend handoff).
@Module({
  controllers: [TicketsController],
  providers: [TicketsService, TicketRepository],
})
export class SupportModule {}
