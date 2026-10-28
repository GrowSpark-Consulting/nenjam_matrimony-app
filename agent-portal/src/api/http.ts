import { ApiError, toApiError } from './errors';
import type { SessionStore } from './session';
import type { AgentSession } from './types';

/**
 * Every call the portal makes is an agent-contract call, so every request
 * carries `Accept-Version: 1` (missing would also mean 1; an unsupported value
 * gives 406). This header belongs to this client only — the Flutter member
 * API is unversioned.
 */
export const ACCEPT_VERSION_HEADER = { 'Accept-Version': '1' } as const;

/** Name of the cross-tab lock that serialises refreshes. */
export const REFRESH_LOCK_NAME = 'nenjam-agent-portal-refresh';

const REFRESH_FAILURE_CODES = new Set([
  'REFRESH_TOKEN_INVALID',
  'REFRESH_TOKEN_EXPIRED',
  'REFRESH_TOKEN_REUSED',
]);

export interface RequestOptions {
  body?: unknown;
  query?: Record<string, string | number | undefined | null>;
  /** Send the agent's bearer token. False for the sign-in calls. */
  auth?: boolean;
}

type LockManagerLike = {
  request<T>(name: string, callback: () => Promise<T>): Promise<T>;
};

function browserLocks(): LockManagerLike | null {
  const locks = typeof navigator === 'undefined' ? undefined : navigator.locks;
  return locks && typeof locks.request === 'function' ? (locks as LockManagerLike) : null;
}

export class HttpClient {
  private readonly baseUrl: string;
  private readonly sessions: SessionStore;
  private readonly fetchFn: typeof fetch;
  private readonly locks: LockManagerLike | null;
  private refreshing: Promise<void> | null = null;

  constructor(
    baseUrl: string,
    sessions: SessionStore,
    fetchFn: typeof fetch = (...args) => fetch(...args),
    locks: LockManagerLike | null = browserLocks(),
  ) {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
    this.sessions = sessions;
    this.fetchFn = fetchFn;
    this.locks = locks;
  }

  async request<T>(method: string, path: string, options: RequestOptions = {}): Promise<T> {
    const { auth = true } = options;
    const usedToken = auth ? (this.sessions.get()?.session.accessToken ?? null) : null;
    try {
      return await this.send<T>(method, path, options);
    } catch (error) {
      // An expired AGENT access token: refresh (serialised across tabs) and
      // retry ONCE. An applicant session has no refresh token and just ends.
      if (
        auth &&
        error instanceof ApiError &&
        error.status === 401 &&
        error.code === 'TOKEN_EXPIRED' &&
        this.sessions.get()?.session.scope === 'AGENT'
      ) {
        await this.refreshOnce(usedToken);
        return this.send<T>(method, path, options);
      }
      if (auth && error instanceof ApiError && error.status === 401) {
        this.sessions.clear();
      }
      throw error;
    }
  }

  /**
   * One refresh at a time. Within this tab concurrent callers share one
   * promise; across tabs a Web Lock serialises them. Two refreshes with the
   * same refresh token count as reuse on the server and sign the agent out
   * everywhere, so this must never race.
   */
  private refreshOnce(staleAccessToken: string | null): Promise<void> {
    if (!this.refreshing) {
      const run = () => this.doRefresh(staleAccessToken);
      this.refreshing = (this.locks ? this.locks.request(REFRESH_LOCK_NAME, run) : run()).finally(
        () => {
          this.refreshing = null;
        },
      );
    }
    return this.refreshing;
  }

  private async doRefresh(staleAccessToken: string | null): Promise<void> {
    // Re-read inside the lock: another tab may have refreshed already, in
    // which case its new tokens are used and the old refresh token is never
    // presented again.
    const current = this.sessions.get()?.session;
    if (!current || current.scope !== 'AGENT') {
      this.sessions.clear();
      throw new ApiError(401, 'Your session has ended. Please sign in again.', {
        code: 'UNAUTHORIZED',
      });
    }
    if (staleAccessToken !== null && current.accessToken !== staleAccessToken) return;
    try {
      const next = await this.send<AgentSession>('POST', '/agent/auth/refresh', {
        auth: false,
        body: { refreshToken: current.refreshToken },
      });
      // The old refresh token stops working: store the new pair.
      this.sessions.set(next);
    } catch (error) {
      if (
        error instanceof ApiError &&
        (error.status === 401 || REFRESH_FAILURE_CODES.has(error.code ?? ''))
      ) {
        this.sessions.clear();
      }
      throw error;
    }
  }

  private async send<T>(method: string, path: string, options: RequestOptions): Promise<T> {
    const { body, query, auth = true } = options;
    const url = new URL(this.baseUrl + path);
    for (const [k, v] of Object.entries(query ?? {})) {
      if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, String(v));
    }
    const headers: Record<string, string> = {
      ...ACCEPT_VERSION_HEADER,
      Accept: 'application/json',
    };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (auth) {
      const token = this.sessions.get()?.session.accessToken;
      if (token) headers.Authorization = `Bearer ${token}`;
    }
    let response: Response;
    try {
      response = await this.fetchFn(url.toString(), {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        // Tokens travel in the header only; never send cookies or referrers.
        credentials: 'omit',
        referrerPolicy: 'no-referrer',
      });
    } catch {
      throw ApiError.network();
    }
    if (response.status === 204) return undefined as T;
    const text = await response.text();
    let parsed: unknown = null;
    if (text) {
      try {
        parsed = JSON.parse(text);
      } catch {
        parsed = null;
      }
    }
    if (!response.ok) {
      throw toApiError(response.status, parsed, response.headers.get('Retry-After'));
    }
    return parsed as T;
  }
}
