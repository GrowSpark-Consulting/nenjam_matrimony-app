import type {
  ReportReason,
  ReportStatus,
} from '../../../../../../libs/database/generated/client';

/** The created report — field-for-field what `POST /users/:id/report` returns. */
export interface ReportResponseDto {
  id: string;
  reason: ReportReason;
  status: ReportStatus;
  createdAt: string;
}

export const REPORT_RESPONSE_EXAMPLE: ReportResponseDto = {
  id: '9a8b7c6d-5e4f-3a2b-1c0d-9e8f7a6b5c4d',
  reason: 'FAKE_PROFILE',
  status: 'OPEN',
  createdAt: '2026-07-25T10:15:00.000Z',
};
