import { AGENT_CONTENT } from '../content/agent-content';
import type { AgentClientDraftRecord } from '../ports/agent-client-ports';
import { clientDraftView } from './client-draft-view';

const NOW = new Date('2026-11-03T10:00:00.000Z');
const DAY = 86_400_000;
const DETAILS = {
  firstName: 'Priya',
  lastName: 'Sundaram',
  gender: 'FEMALE' as const,
  dob: '1998-04-12',
  maritalStatus: 'NEVER_MARRIED' as const,
  profileCreatedFor: 'Daughter' as const,
};

const row = (
  o: Partial<AgentClientDraftRecord> = {},
): AgentClientDraftRecord => ({
  id: 'draft-1',
  agentId: 'agent-1',
  status: 'DRAFT',
  phoneHash: 'v1:hash',
  phoneSealed: 'sealed-phone',
  phoneMasked: '+91 98***210',
  displayName: 'Priya S.',
  detailsSealed: 'sealed-details',
  expiresAt: new Date(NOW.getTime() + 14 * DAY),
  submittedAt: null,
  acceptedAt: null,
  closedAt: null,
  closedReason: null,
  memberId: null,
  attributionId: null,
  createdAt: new Date(NOW.getTime() - DAY),
  ...o,
});

const view = (r: AgentClientDraftRecord) =>
  clientDraftView(r, NOW, {
    labels: AGENT_CONTENT.clientStatusLabels,
    details: DETAILS,
  });

describe('clientDraftView', () => {
  it('shows an open DRAFT with its details, editable', () => {
    expect(view(row())).toEqual({
      id: 'draft-1',
      status: 'DRAFT',
      statusLabel: AGENT_CONTENT.clientStatusLabels.DRAFT,
      displayName: 'Priya S.',
      phoneMasked: '+91 98***210',
      details: DETAILS,
      editable: true,
      createdAt: '2026-11-02T10:00:00.000Z',
      submittedOn: null,
      expiresOn: '2026-11-17',
      acceptedOn: null,
      referralId: null,
    });
  });

  it('a waiting draft still shows its details but is not editable', () => {
    const v = view(
      row({
        status: 'WAITING_FOR_CLIENT',
        submittedAt: new Date('2026-11-02T20:00:00.000Z'),
      }),
    );
    expect(v).toMatchObject({
      status: 'WAITING_FOR_CLIENT',
      editable: false,
      details: DETAILS,
    });
    // 20:00 UTC is already the next day in India.
    expect(v.submittedOn).toBe('2026-11-03');
  });

  it('an open draft past its time is EXPIRED, without details, before the job runs', () => {
    for (const status of ['DRAFT', 'WAITING_FOR_CLIENT'] as const) {
      const v = view(row({ status, expiresAt: NOW }));
      expect(v).toMatchObject({
        status: 'EXPIRED',
        details: null,
        editable: false,
      });
      expect(v.statusLabel).toEqual(AGENT_CONTENT.clientStatusLabels.EXPIRED);
    }
  });

  it('a closed draft never shows details, even if the caller passed them', () => {
    for (const status of ['REJECTED', 'EXPIRED'] as const) {
      expect(view(row({ status, detailsSealed: null })).details).toBeNull();
    }
  });

  it('an accepted draft links its referral and shows the day it was accepted', () => {
    const v = view(
      row({
        status: 'ACCEPTED',
        detailsSealed: null,
        phoneSealed: null,
        acceptedAt: new Date('2026-11-03T09:00:00.000Z'),
        attributionId: 'attribution-1',
        memberId: 'member-1',
      }),
    );
    expect(v).toMatchObject({
      status: 'ACCEPTED',
      details: null,
      acceptedOn: '2026-11-03',
      referralId: 'attribution-1',
    });
  });

  it('never carries the phone hash, the sealed values or the member id', () => {
    const text = JSON.stringify(view(row({ memberId: 'member-1' })));
    for (const secret of [
      'v1:hash',
      'sealed-phone',
      'sealed-details',
      'member-1',
    ]) {
      expect(text).not.toContain(secret);
    }
  });
});
