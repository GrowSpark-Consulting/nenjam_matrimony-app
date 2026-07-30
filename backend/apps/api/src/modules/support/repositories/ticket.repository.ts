import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  SupportTicket,
  SupportTicketType,
} from '../../../../../../libs/database/generated/client';

/** The columns needed to persist a new ticket — already mapped to DB terms
 *  (`body`, Prisma enum) by the service, so this layer stays ORM-only. */
export interface CreateTicketData {
  userId: string;
  type: SupportTicketType;
  subject: string;
  body: string;
}

/**
 * Persistence for support tickets. DB access only — no mapping, validation, or
 * business rules. Every query is scoped by `userId` so a caller can only ever
 * touch their own tickets.
 */
@Injectable()
export class TicketRepository {
  constructor(private readonly prisma: PrismaService) {}

  createTicket(data: CreateTicketData): Promise<SupportTicket> {
    return this.prisma.supportTicket.create({ data });
  }

  /** The caller's tickets, newest first. */
  findTicketsByUser(userId: string): Promise<SupportTicket[]> {
    return this.prisma.supportTicket.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
  }
}
