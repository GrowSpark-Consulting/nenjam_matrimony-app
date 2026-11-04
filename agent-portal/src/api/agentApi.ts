import type { HttpClient } from './http';
import type {
  AgentConfig,
  AgentProfile,
  AgentSession,
  ApplicationInput,
  Balance,
  ClientDetails,
  ClientDraft,
  ClientStatus,
  Commission,
  CreateClientInput,
  CommissionStatus,
  OtpRequestResponse,
  Page,
  Payout,
  PayoutDetailsInput,
  PayoutDetailsSummary,
  RefItem,
  ReferralLink,
  ReferralStage,
  ReferralView,
  Session,
} from './types';

export interface PageQuery {
  cursor?: string | null;
  limit?: number;
}

/**
 * Every agent endpoint the portal uses. `HttpAgentApi` talks to the backend;
 * `MockAgentApi` stands in until the endpoints are built (they are designed,
 * not implemented — see docs/agent-program/FRONTEND_HANDOFF_DHATRI.md §8).
 *
 * There is deliberately no "create payout" call: payouts are an admin action.
 */
export interface AgentApi {
  requestOtp(phone: string): Promise<OtpRequestResponse>;
  verifyOtp(challengeId: string, code: string): Promise<Session>;
  logout(refreshToken: string): Promise<void>;
  /** Returns a full AgentSession — no second OTP after applying. */
  apply(input: ApplicationInput): Promise<AgentSession>;
  /** Rejects with a 404 ApiError for an applicant (no agent record yet). */
  getMe(): Promise<AgentProfile>;
  getConfig(): Promise<AgentConfig>;
  getReferralLinks(): Promise<ReferralLink[]>;
  getReferrals(query: PageQuery & { stage?: ReferralStage }): Promise<Page<ReferralView>>;
  getCommissions(query: PageQuery & { status?: CommissionStatus }): Promise<Page<Commission>>;
  getBalance(): Promise<Balance>;
  getPayouts(query: PageQuery): Promise<Page<Payout>>;
  updatePayoutDetails(input: PayoutDetailsInput): Promise<PayoutDetailsSummary>;

  // Way 2: agent-added clients (docs/agent-program/HANDOFF_WAY2_FRONTEND.md).
  listClients(query: PageQuery & { status?: ClientStatus }): Promise<Page<ClientDraft>>;
  getClient(id: string): Promise<ClientDraft>;
  createClient(input: CreateClientInput): Promise<ClientDraft>;
  /** Replaces the WHOLE `details`: always send the complete merged profile. */
  updateClient(id: string, details: ClientDetails): Promise<ClientDraft>;
  deleteClient(id: string): Promise<void>;
  submitClient(id: string): Promise<ClientDraft>;

  // Master data for the profile form. No token needed.
  getReligions(): Promise<RefItem[]>;
  getCommunities(religionCode: string): Promise<RefItem[]>;
  getCountries(): Promise<RefItem[]>;
  getStates(countryCode: string): Promise<RefItem[]>;
  getCities(stateCode: string): Promise<RefItem[]>;
}

export class HttpAgentApi implements AgentApi {
  private readonly http: HttpClient;

  constructor(http: HttpClient) {
    this.http = http;
  }

  requestOtp(phone: string) {
    return this.http.request<OtpRequestResponse>('POST', '/agent/auth/otp/request', {
      auth: false,
      body: { phone },
    });
  }

  verifyOtp(challengeId: string, code: string) {
    return this.http.request<Session>('POST', '/agent/auth/otp/verify', {
      auth: false,
      body: { challengeId, code },
    });
  }

  logout(refreshToken: string) {
    return this.http.request<void>('POST', '/agent/auth/logout', { body: { refreshToken } });
  }

  apply(input: ApplicationInput) {
    return this.http.request<AgentSession>('POST', '/agent/application', { body: input });
  }

  getMe() {
    return this.http.request<AgentProfile>('GET', '/agent/me');
  }

  getConfig() {
    return this.http.request<AgentConfig>('GET', '/agent/config');
  }

  async getReferralLinks() {
    const res = await this.http.request<{ items: ReferralLink[] }>('GET', '/agent/referral-links');
    return res.items;
  }

  getReferrals(query: PageQuery & { stage?: ReferralStage }) {
    return this.http.request<Page<ReferralView>>('GET', '/agent/referrals', { query: { ...query } });
  }

  getCommissions(query: PageQuery & { status?: CommissionStatus }) {
    return this.http.request<Page<Commission>>('GET', '/agent/commissions', { query: { ...query } });
  }

  getBalance() {
    return this.http.request<Balance>('GET', '/agent/balance');
  }

  getPayouts(query: PageQuery) {
    return this.http.request<Page<Payout>>('GET', '/agent/payouts', { query: { ...query } });
  }

  updatePayoutDetails(input: PayoutDetailsInput) {
    return this.http.request<PayoutDetailsSummary>('PATCH', '/agent/me/payout-details', {
      body: input,
    });
  }

  listClients(query: PageQuery & { status?: ClientStatus }) {
    return this.http.request<Page<ClientDraft>>('GET', '/agent/clients', { query: { ...query } });
  }

  getClient(id: string) {
    return this.http.request<ClientDraft>('GET', `/agent/clients/${encodeURIComponent(id)}`);
  }

  createClient(input: CreateClientInput) {
    return this.http.request<ClientDraft>('POST', '/agent/clients', { body: input });
  }

  updateClient(id: string, details: ClientDetails) {
    return this.http.request<ClientDraft>('PATCH', `/agent/clients/${encodeURIComponent(id)}`, {
      body: { details },
    });
  }

  deleteClient(id: string) {
    return this.http.request<void>('DELETE', `/agent/clients/${encodeURIComponent(id)}`);
  }

  submitClient(id: string) {
    return this.http.request<ClientDraft>(
      'POST',
      `/agent/clients/${encodeURIComponent(id)}/submit`,
    );
  }

  getReligions() {
    return this.http.request<RefItem[]>('GET', '/reference-data/religions', { auth: false });
  }

  getCommunities(religionCode: string) {
    return this.http.request<RefItem[]>('GET', '/reference-data/communities', {
      auth: false,
      query: { religionCode },
    });
  }

  getCountries() {
    return this.http.request<RefItem[]>('GET', '/reference-data/countries', { auth: false });
  }

  getStates(countryCode: string) {
    return this.http.request<RefItem[]>('GET', '/reference-data/states', {
      auth: false,
      query: { countryCode },
    });
  }

  getCities(stateCode: string) {
    return this.http.request<RefItem[]>('GET', '/reference-data/cities', {
      auth: false,
      query: { stateCode },
    });
  }
}
