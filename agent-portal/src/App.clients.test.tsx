import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import type { ApiSetup } from './api';
import { ApiError } from './api/errors';
import { MockAgentApi } from './api/mockAgentApi';
import { SessionStore } from './api/session';
import type {
  AgentConfig,
  ClientDetails,
  ClientDraft,
  ClientStatus,
  CreateClientInput,
  Page,
  RefItem,
} from './api/types';
import { AppRoutes } from './App';
import { REQUIRED_PATHS, isAnswered } from './lib/clientProfile';
import { PortalProvider } from './state/PortalContext';

/**
 * Way 2 client form against a FAKE API that mimics the documented rules
 * (PATCH replaces `details`, missingRequired from the nine paths, expiry set
 * at creation and restarted only on submit). Proves the portal's logic, not
 * the live backend: the feature switch there is off.
 */

const ACTIVE = '+919000000005';
const SUSPENDED = '+919000000003';

class ClientsApi extends MockAgentApi {
  enabled = true;
  draft: ClientDraft = makeDraft({});
  patches: ClientDetails[] = [];
  submits = 0;
  deleted = 0;
  submitError: unknown = null;
  list: ClientDraft[] = [];

  override async getConfig(): Promise<AgentConfig> {
    const base = await super.getConfig();
    return {
      ...base,
      clientStatusLabels: {
        DRAFT: { en: 'Draft', ta: '<to be supplied>' },
        WAITING_FOR_CLIENT: { en: 'Waiting for client', ta: '<to be supplied>' },
        ACCEPTED: { en: 'Accepted', ta: '<to be supplied>' },
        REJECTED: { en: 'Declined', ta: '<to be supplied>' },
        EXPIRED: { en: 'Expired', ta: '<to be supplied>' },
      },
      clients: this.enabled ? { enabled: true, draftLimit: 10, expiryDays: 14 } : undefined,
    };
  }
  override async listClients(): Promise<Page<ClientDraft>> {
    return { items: this.list, nextCursor: null };
  }
  override async getClient(): Promise<ClientDraft> {
    return this.draft;
  }
  override async createClient(input: CreateClientInput): Promise<ClientDraft> {
    this.draft = makeDraft(input.details ?? {});
    return this.draft;
  }
  override async updateClient(_id: string, details: ClientDetails): Promise<ClientDraft> {
    this.patches.push(JSON.parse(JSON.stringify(details)));
    // Expiry is NOT touched by an edit.
    this.draft = { ...makeDraft(details), expiresOn: this.draft.expiresOn };
    return this.draft;
  }
  override async submitClient(): Promise<ClientDraft> {
    this.submits++;
    if (this.submitError) throw this.submitError;
    this.draft = {
      ...this.draft,
      status: 'WAITING_FOR_CLIENT',
      statusLabel: { en: 'Waiting for client', ta: '' },
      editable: false,
      submittedOn: '2026-11-20',
      expiresOn: '2026-12-04', // restarted by the BACKEND, not computed here
    };
    return this.draft;
  }
  override async deleteClient(): Promise<void> {
    this.deleted++;
  }
  override async getReligions(): Promise<RefItem[]> {
    return [
      { code: 'HINDU', label: 'Hindu' },
      { code: 'CHRISTIAN', label: 'Christian' },
    ];
  }
  override async getCommunities(r: string): Promise<RefItem[]> {
    return r === 'HINDU' ? [{ code: 'HINDU-VELLALAR', label: 'Vellalar' }] : [];
  }
  override async getCountries(): Promise<RefItem[]> {
    return [{ code: 'IN', label: 'India' }];
  }
  override async getStates(): Promise<RefItem[]> {
    return [{ code: 'IN-TN', label: 'Tamil Nadu' }];
  }
  override async getCities(): Promise<RefItem[]> {
    return [{ code: 'IN-TN-MADURAI', label: 'Madurai' }];
  }
}

function makeDraft(details: ClientDetails, over: Partial<ClientDraft> = {}): ClientDraft {
  return {
    id: 'c1',
    status: 'DRAFT',
    statusLabel: { en: 'Draft', ta: '<to be supplied>' },
    displayName: 'Priya S.',
    phoneMasked: '+91 98***210',
    details,
    missingRequired: REQUIRED_PATHS.filter((p) => !isAnswered(details, p)),
    editable: true,
    createdAt: '2026-11-06T10:00:00.000Z',
    submittedOn: null,
    expiresOn: '2026-11-20',
    acceptedOn: null,
    referralId: null,
    ...over,
  };
}

const COMPLETE: ClientDetails = {
  basicDetails: { firstName: 'Priya', lastName: 'Sundaram', gender: 'FEMALE', dob: '1998-04-12', maritalStatus: 'NEVER_MARRIED' },
  religionDetails: { religionCode: 'HINDU', religion: 'Hindu' },
  locationDetails: { countryCode: 'IN', stateCode: 'IN-TN', cityCode: 'IN-TN-MADURAI' },
  educationDetails: { qualification: 'MBA / PGDM' },
  physicalDetails: { height: '5\'9" (175 cm)' },
  partnerPreference: { preferredAgeRange: '26-30' },
};

async function renderAt(path: string, tweak: (api: ClientsApi) => void = () => {}, phone = ACTIVE) {
  window.localStorage.clear();
  const sessions = new SessionStore(window.localStorage);
  const api = new ClientsApi(sessions);
  tweak(api);
  const { challengeId } = await api.requestOtp(phone);
  sessions.set(await api.verifyOtp(challengeId, '123456'));
  const setup: ApiSetup = { api, sessions, usingMocks: true };
  render(
    <PortalProvider setup={setup}>
      <MemoryRouter initialEntries={[path]}>
        <AppRoutes />
      </MemoryRouter>
    </PortalProvider>,
  );
  return api;
}

describe('feature gate', () => {
  it('is hidden when clients.enabled is off or the object is missing', async () => {
    await renderAt('/clients', (a) => (a.enabled = false));
    await screen.findByLabelText('Referral code');
    expect(screen.queryByText('Your clients')).toBeNull();
    expect(screen.queryByRole('link', { name: 'Your clients' })).toBeNull();
  });

  it('shows the menu entry and the list when enabled', async () => {
    await renderAt('/clients', (a) => (a.list = [makeDraft({})]));
    expect(await screen.findByRole('heading', { name: 'Your clients' })).toBeInTheDocument();
    expect(screen.getAllByRole('link', { name: 'Your clients' }).length).toBeGreaterThan(0);
    expect(await screen.findByLabelText('Open clients')).toHaveTextContent('1 of 10 open');
  });

  it('a paused agent sees the list read-only (no Add button)', async () => {
    await renderAt('/clients', (a) => (a.list = [makeDraft({})]), SUSPENDED);
    await screen.findByRole('heading', { name: 'Your clients' });
    expect(screen.queryByRole('link', { name: 'Add a client' })).toBeNull();
    expect(screen.getByText(/account is paused/)).toBeInTheDocument();
  });
});

describe('required count comes from the backend', () => {
  it('shows 5 when the backend lists 5, and 9 when it lists 9 (not a fixed number)', async () => {
    const five = makeDraft({
      basicDetails: { firstName: 'Priya', lastName: 'S', gender: 'FEMALE', dob: '1998-04-12' },
    });
    expect(five.missingRequired).toHaveLength(5);
    await renderAt('/clients/c1', (a) => (a.draft = five));
    expect(await screen.findByLabelText('Required fields left')).toHaveTextContent('5 required fields left');
  });

  it('9 missing on an empty draft; Submit is disabled', async () => {
    const user = userEvent.setup();
    await renderAt('/clients/c1');
    expect(await screen.findByLabelText('Required fields left')).toHaveTextContent('9 required fields left');
    await user.click(screen.getByRole('button', { name: 'Review' }));
    expect(screen.getByRole('button', { name: 'Submit to client' })).toBeDisabled();
  });

  it('marks required fields from missingRequired', async () => {
    const user = userEvent.setup();
    await renderAt('/clients/c1', (a) => (a.draft = makeDraft(COMPLETE)));
    await screen.findByLabelText('Required fields left');
    expect(screen.getByLabelText('Required fields left')).toHaveTextContent('All required details are filled in');
    await user.click(screen.getByRole('button', { name: 'Review' }));
    expect(screen.getByRole('button', { name: 'Submit to client' })).toBeEnabled();
    expect(screen.queryByText(/\(required\)/)).toBeNull();
  });
});

describe('PATCH sends the full merged profile', () => {
  it('editing basic details keeps religion, location, education, height and preferences', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/clients/c1', (a) => (a.draft = makeDraft(COMPLETE)));
    const first = await screen.findByLabelText('First name');
    await user.clear(first);
    await user.type(first, 'Divya');
    await user.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(api.patches).toHaveLength(1));
    const sent = api.patches[0] as Record<string, Record<string, unknown>>;
    expect(sent.basicDetails.firstName).toBe('Divya');
    expect(sent.basicDetails.lastName).toBe('Sundaram');
    expect(sent.religionDetails).toEqual({ religionCode: 'HINDU' });
    expect(sent.locationDetails).toEqual({ countryCode: 'IN', stateCode: 'IN-TN', cityCode: 'IN-TN-MADURAI' });
    expect(sent.educationDetails).toEqual({ qualification: 'MBA / PGDM' });
    expect(sent.physicalDetails).toEqual({ height: '5\'9" (175 cm)' });
    expect(sent.partnerPreference).toEqual({ preferredAgeRange: '26-30' });
  });

  it('never sends an empty details or empty sections', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/clients/c1', (a) => (a.draft = makeDraft({ basicDetails: { firstName: 'Priya' } })));
    await user.type(await screen.findByLabelText(/^Last name/), '   ');
    await user.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(api.patches).toHaveLength(1));
    expect(api.patches[0]).toEqual({ basicDetails: { firstName: 'Priya' } });
  });

  it('a section edited then left empty again is dropped, others stay', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/clients/c1', (a) => (a.draft = makeDraft(COMPLETE)));
    await user.click(await screen.findByRole('button', { name: 'Physical' }));
    await user.selectOptions(screen.getByLabelText('Height'), '');
    await user.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(api.patches).toHaveLength(1));
    const sent = api.patches[0];
    expect(sent).not.toHaveProperty('physicalDetails');
    expect(sent).toHaveProperty('basicDetails');
    expect(sent).toHaveProperty('educationDetails');
  });

  it('height is sent as the exact app label', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/clients/c1', (a) => (a.draft = makeDraft(COMPLETE)));
    await user.click(await screen.findByRole('button', { name: 'Physical' }));
    await user.selectOptions(screen.getByLabelText('Height'), '5\'3" (160 cm)');
    await user.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(api.patches).toHaveLength(1));
    expect((api.patches[0] as Record<string, Record<string, unknown>>).physicalDetails.height).toBe('5\'3" (160 cm)');
  });
});

describe('Skip', () => {
  it('moves on without clearing or saving; returning restores the typed value', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/clients/c1', (a) => (a.draft = makeDraft(COMPLETE)));
    const first = await screen.findByLabelText('First name');
    await user.clear(first);
    await user.type(first, 'Divya');
    await user.click(screen.getByRole('button', { name: 'Skip' }));
    expect(await screen.findByRole('heading', { name: 'Religion' })).toBeInTheDocument();
    expect(api.patches).toHaveLength(0);
    await user.click(screen.getByRole('button', { name: 'Basic details' }));
    expect(screen.getByLabelText('First name')).toHaveValue('Divya');
    // Other sections' saved values are intact, too.
    await user.click(screen.getByRole('button', { name: 'Education and work' }));
    expect(screen.getByLabelText('Highest education')).toHaveValue('MBA / PGDM');
  });
});

describe('community and religion', () => {
  it('community is optional (not marked required) and clears when religion changes', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/clients/c1', (a) => {
      a.draft = makeDraft({
        ...COMPLETE,
        religionDetails: { religionCode: 'HINDU', communityCode: 'HINDU-VELLALAR' },
      });
    });
    await user.click(await screen.findByRole('button', { name: 'Religion' }));
    await waitFor(() => expect(screen.getByLabelText('Community')).toHaveValue('HINDU-VELLALAR'));
    expect(screen.getByText('Community')).toBeInTheDocument();
    await user.selectOptions(screen.getByLabelText('Religion'), 'CHRISTIAN');
    expect(screen.getByLabelText('Community')).toHaveValue('');
    await user.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(api.patches).toHaveLength(1));
    expect((api.patches[0] as Record<string, Record<string, unknown>>).religionDetails).toEqual({
      religionCode: 'CHRISTIAN',
    });
  });
});

describe('siblings', () => {
  it('a row with no relation blocks the save and nothing is sent', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/clients/c1', (a) => (a.draft = makeDraft(COMPLETE)));
    await user.click(await screen.findByRole('button', { name: 'Family' }));
    await user.click(screen.getByRole('button', { name: 'Add a sibling' }));
    await user.type(screen.getByLabelText('Sibling 1 name'), 'Arun');
    await user.click(screen.getByRole('button', { name: 'Save' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Choose brother or sister');
    expect(api.patches).toHaveLength(0);
  });

  it('empty age is omitted, numeric age is a number', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/clients/c1', (a) => (a.draft = makeDraft(COMPLETE)));
    await user.click(await screen.findByRole('button', { name: 'Family' }));
    await user.click(screen.getByRole('button', { name: 'Add a sibling' }));
    await user.selectOptions(screen.getByLabelText('Sibling 1 relation'), 'BROTHER');
    await user.click(screen.getByRole('button', { name: 'Add a sibling' }));
    await user.selectOptions(screen.getByLabelText('Sibling 2 relation'), 'SISTER');
    await user.type(screen.getByLabelText('Sibling 2 age'), '25');
    await user.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(api.patches).toHaveLength(1));
    const rows = (api.patches[0] as { familyDetails: { siblings: Record<string, unknown>[] } }).familyDetails.siblings;
    expect(rows[0]).toEqual({ relation: 'BROTHER' });
    expect('age' in rows[0]).toBe(false);
    expect(rows[1]).toEqual({ relation: 'SISTER', age: 25 });
  });
});

describe('expiry', () => {
  it('editing keeps the backend expiry; submit shows the backend restarted one', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/clients/c1', (a) => (a.draft = makeDraft(COMPLETE)));
    expect(await screen.findByText(/Open until 2026-11-20/)).toBeInTheDocument();
    const first = screen.getByLabelText('First name');
    await user.clear(first);
    await user.type(first, 'Divya');
    await user.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(api.patches).toHaveLength(1));
    expect(screen.getByText(/Open until 2026-11-20/)).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Review' }));
    await user.click(screen.getByRole('button', { name: 'Submit to client' }));
    expect(screen.getByText(/can't change it/)).toBeInTheDocument();
    expect(api.submits).toBe(0);
    await user.click(screen.getByRole('button', { name: 'Yes, submit' }));
    expect(await screen.findByText(/Waiting until 2026-12-04/)).toBeInTheDocument();
    expect(api.submits).toBe(1);
  });
});

describe('submit errors', () => {
  it('CLIENT_PROFILE_INCOMPLETE opens the first missing field', async () => {
    const user = userEvent.setup();
    const err = new ApiError(422, 'x', { code: 'CLIENT_PROFILE_INCOMPLETE', missingFields: ['educationDetails.qualification'] });
    await renderAt('/clients/c1', (a) => {
      a.draft = makeDraft(COMPLETE);
      a.submitError = err;
    });
    await user.click(await screen.findByRole('button', { name: 'Review' }));
    await user.click(screen.getByRole('button', { name: 'Submit to client' }));
    await user.click(screen.getByRole('button', { name: 'Yes, submit' }));
    expect(await screen.findByRole('heading', { name: 'Education and work' })).toBeInTheDocument();
    expect(screen.getByRole('alert')).toHaveTextContent('Highest education');
  });

  it('CLIENT_PHONE_UNAVAILABLE keeps the draft (nothing is deleted)', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/clients/c1', (a) => {
      a.draft = makeDraft(COMPLETE);
      a.submitError = new ApiError(422, 'x', { code: 'CLIENT_PHONE_UNAVAILABLE' });
    });
    await user.click(await screen.findByRole('button', { name: 'Review' }));
    await user.click(screen.getByRole('button', { name: 'Submit to client' }));
    await user.click(screen.getByRole('button', { name: 'Yes, submit' }));
    expect(await screen.findByRole('alert')).toHaveTextContent("can't be added");
    expect(api.deleted).toBe(0);
    expect(screen.getByRole('button', { name: 'Discard' })).toBeInTheDocument();
  });
});

describe('closed drafts', () => {
  it('a waiting draft is read-only and shows no editor', async () => {
    await renderAt('/clients/c1', (a) => {
      a.draft = makeDraft(COMPLETE, { status: 'WAITING_FOR_CLIENT' as ClientStatus, editable: false, expiresOn: '2026-12-04' });
    });
    expect(await screen.findByText(/Waiting until 2026-12-04/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Submit to client' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Save' })).toBeNull();
    const profile = screen.getByRole('region', { name: 'Religion' });
    expect(within(profile).getByText('Hindu')).toBeInTheDocument();
  });
});
