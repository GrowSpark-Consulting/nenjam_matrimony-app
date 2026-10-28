import type { HttpClient } from './http';
import type {
  AgentConfig,
  AgentProfile,
  AgentSession,
  ApplicationInput,
  Balance,
  Commission,
  CommissionStatus,
  OtpRequestResponse,
  Page,
  Payout,
  PayoutDetailsInput,
  PayoutDetailsSummary,
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
}
