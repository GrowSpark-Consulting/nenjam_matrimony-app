import { BadRequestException } from '@nestjs/common';
import { TicketsService } from '../services/tickets.service';
import { CreateTicketDto } from '../dto/create-ticket.dto';
import { SupportTicketTypeWire } from '../dto/support-ticket.response.dto';
import type { SupportTicket } from '../../../../../../libs/database/generated/client';

function ticket(over: Partial<SupportTicket> = {}): SupportTicket {
  return {
    id: 't1',
    userId: 'u1',
    type: 'BUG_REPORT',
    subject: 'Crash',
    body: 'App crashes after login.',
    status: 'OPEN',
    adminResponse: null,
    resolvedAt: null,
    createdAt: new Date('2026-07-30T10:00:00.000Z'),
    updatedAt: new Date('2026-07-30T10:00:00.000Z'),
    ...over,
  };
}

function build() {
  const ticketRepository = {
    createTicket: jest.fn(),
    findTicketsByUser: jest.fn(),
  };
  const service = new TicketsService(ticketRepository as never);
  return { service, ticketRepository };
}

const dto = (over: Partial<CreateTicketDto> = {}): CreateTicketDto => ({
  type: SupportTicketTypeWire.bugReport,
  subject: 'Crash',
  message: 'App crashes after login.',
  ...over,
});

describe('TicketsService.createTicket', () => {
  it('persists with message→body + wire→Prisma enum mapping and returns a wire DTO', async () => {
    const { service, ticketRepository } = build();
    ticketRepository.createTicket.mockResolvedValue(ticket());

    const result = await service.createTicket('u1', dto());

    expect(ticketRepository.createTicket).toHaveBeenCalledWith({
      userId: 'u1',
      type: 'BUG_REPORT',
      subject: 'Crash',
      body: 'App crashes after login.',
    });
    expect(result).toEqual({
      id: 't1',
      type: 'bugReport',
      subject: 'Crash',
      message: 'App crashes after login.',
      status: 'open',
      createdAt: '2026-07-30T10:00:00.000Z',
    });
  });

  it('trims subject and message before persisting', async () => {
    const { service, ticketRepository } = build();
    ticketRepository.createTicket.mockResolvedValue(ticket());

    await service.createTicket(
      'u1',
      dto({ subject: '  Crash  ', message: '  hello  ' }),
    );

    const calls = ticketRepository.createTicket.mock.calls as unknown[][];
    expect(calls[0][0]).toMatchObject({ subject: 'Crash', body: 'hello' });
  });

  it('rejects whitespace-only subject or message (never hits the repo)', async () => {
    const { service, ticketRepository } = build();
    await expect(
      service.createTicket('u1', dto({ subject: '   ' })),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      service.createTicket('u1', dto({ message: '   ' })),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(ticketRepository.createTicket).not.toHaveBeenCalled();
  });
});

describe('TicketsService.getMyTickets', () => {
  it('returns the caller tickets in a list envelope, mapped to wire DTOs', async () => {
    const { service, ticketRepository } = build();
    ticketRepository.findTicketsByUser.mockResolvedValue([
      ticket({ id: 'a', type: 'CONTACT_SUPPORT', status: 'CLOSED' }),
      ticket({ id: 'b', type: 'FEATURE_REQUEST', status: 'IN_PROGRESS' }),
    ]);

    const result = await service.getMyTickets('u1');

    expect(ticketRepository.findTicketsByUser).toHaveBeenCalledWith('u1');
    expect(result.items.map((t) => [t.id, t.type, t.status])).toEqual([
      ['a', 'contactSupport', 'closed'],
      ['b', 'featureRequest', 'inProgress'],
    ]);
  });

  it('returns an empty envelope when there are no tickets', async () => {
    const { service, ticketRepository } = build();
    ticketRepository.findTicketsByUser.mockResolvedValue([]);
    await expect(service.getMyTickets('u1')).resolves.toEqual({ items: [] });
  });
});
