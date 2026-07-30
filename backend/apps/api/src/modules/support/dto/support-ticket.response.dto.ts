/**
 * The API-facing (wire) enums for support tickets. Deliberately distinct from
 * the Prisma enums so the internal ORM naming never leaks onto the wire — the
 * mapper (`support-ticket.mapper.ts`) is the only place the two are bridged.
 * Values are lowerCamelCase to match the Flutter client's enum `.name`s.
 */
export enum SupportTicketTypeWire {
  contactSupport = 'contactSupport',
  bugReport = 'bugReport',
  featureRequest = 'featureRequest',
  appFeedback = 'appFeedback',
}

export enum SupportTicketStatusWire {
  open = 'open',
  inProgress = 'inProgress',
  resolved = 'resolved',
  closed = 'closed',
}

/** A single support ticket on the wire. `message` is the API name for the DB
 *  `body` column; `createdAt` is an ISO-8601 string. */
export interface SupportTicketResponseDto {
  id: string;
  type: SupportTicketTypeWire;
  subject: string;
  message: string;
  status: SupportTicketStatusWire;
  createdAt: string;
}

/** Ticket history is always returned as an envelope so cursor/page fields can be
 *  added later without breaking the `{ items: [...] }` shape clients read. */
export interface SupportTicketListResponseDto {
  items: SupportTicketResponseDto[];
}
