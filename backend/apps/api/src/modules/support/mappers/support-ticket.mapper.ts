import type {
  SupportStatus,
  SupportTicket,
  SupportTicketType,
} from '../../../../../../libs/database/generated/client';
import {
  SupportTicketResponseDto,
  SupportTicketStatusWire,
  SupportTicketTypeWire,
} from '../dto/support-ticket.response.dto';

// Prisma enum → wire enum. Exhaustive `Record`s so adding a Prisma enum value
// without a wire mapping is a compile error, not a runtime surprise.
const TYPE_TO_WIRE: Record<SupportTicketType, SupportTicketTypeWire> = {
  CONTACT_SUPPORT: SupportTicketTypeWire.contactSupport,
  BUG_REPORT: SupportTicketTypeWire.bugReport,
  FEATURE_REQUEST: SupportTicketTypeWire.featureRequest,
  APP_FEEDBACK: SupportTicketTypeWire.appFeedback,
};

const TYPE_TO_PRISMA: Record<SupportTicketTypeWire, SupportTicketType> = {
  [SupportTicketTypeWire.contactSupport]: 'CONTACT_SUPPORT',
  [SupportTicketTypeWire.bugReport]: 'BUG_REPORT',
  [SupportTicketTypeWire.featureRequest]: 'FEATURE_REQUEST',
  [SupportTicketTypeWire.appFeedback]: 'APP_FEEDBACK',
};

const STATUS_TO_WIRE: Record<SupportStatus, SupportTicketStatusWire> = {
  OPEN: SupportTicketStatusWire.open,
  IN_PROGRESS: SupportTicketStatusWire.inProgress,
  RESOLVED: SupportTicketStatusWire.resolved,
  CLOSED: SupportTicketStatusWire.closed,
};

/** Wire ticket type → Prisma enum, for persisting a newly-created ticket. */
export function ticketTypeToPrisma(
  type: SupportTicketTypeWire,
): SupportTicketType {
  return TYPE_TO_PRISMA[type];
}

/** Prisma row → wire DTO. Maps `body`→`message`, both enums to their wire form,
 *  and `createdAt` to ISO-8601 — nothing else on the Prisma model is exposed. */
export function toSupportTicketResponse(
  ticket: SupportTicket,
): SupportTicketResponseDto {
  return {
    id: ticket.id,
    type: TYPE_TO_WIRE[ticket.type],
    subject: ticket.subject,
    message: ticket.body,
    status: STATUS_TO_WIRE[ticket.status],
    createdAt: ticket.createdAt.toISOString(),
  };
}
