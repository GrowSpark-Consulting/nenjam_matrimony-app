/**
 * The only way this app talks to the backend. Every request carries the
 * Firebase ID token (who you are) and, after the authenticator step, the
 * admin session token (proof of the second factor). The API decides
 * everything; errors come back as Nest's shape plus a stable `code`.
 */

export interface ApiErrorBody {
  statusCode?: number;
  error?: string;
  code?: string;
  message?: string | string[];
  [key: string]: unknown;
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code: string | undefined,
    readonly body: ApiErrorBody,
  ) {
    super(message);
    this.name = 'ApiError';
  }

  /** The admin session is missing, expired or idle: enter a new code. */
  get needsSecondFactor(): boolean {
    return (
      this.status === 401 &&
      (this.code === 'ADMIN_SESSION_REQUIRED' ||
        this.code === 'ADMIN_SESSION_INVALID')
    );
  }

  get needsStepUp(): boolean {
    return this.status === 401 && this.code === 'ADMIN_STEP_UP_REQUIRED';
  }
}

/** A readable sentence from any error body (validation errors are a list). */
export function errorMessage(status: number, body: ApiErrorBody | null): string {
  const raw = body?.message;
  if (Array.isArray(raw) && raw.length > 0) return raw.join(' ');
  if (typeof raw === 'string' && raw.trim()) return raw;
  if (status === 0) return 'Could not reach the server. Check your connection.';
  if (status === 401) return 'Please sign in again.';
  if (status === 403) return 'You don’t have access to this.';
  if (status === 404) return 'Not found.';
  if (status === 429) return 'Too many attempts. Please wait and try again.';
  if (status >= 500) return 'The server had a problem. Please try again.';
  return `Request failed (${status}).`;
}

export type Query = Record<string, string | number | undefined | null>;

export function buildUrl(base: string, path: string, query?: Query): string {
  const url = `${base}${path.startsWith('/') ? path : `/${path}`}`;
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== undefined && value !== null && value !== '') {
      params.set(key, String(value));
    }
  }
  const qs = params.toString();
  return qs ? `${url}?${qs}` : url;
}

export interface ApiClientOptions {
  baseUrl: string;
  /** A fresh Firebase ID token, or null when signed out. */
  getIdToken: () => Promise<string | null>;
  getSessionToken: () => string | null;
  /** Called on a 401 asking for a fresh authenticator code; resolves true
   *  once the admin has confirmed one, so the request is retried once. */
  onStepUpRequired?: () => Promise<boolean>;
  /** Called when the admin session is gone (expired, idle, revoked). */
  onSessionLost?: () => void;
  fetchImpl?: typeof fetch;
}

export class ApiClient {
  constructor(private readonly options: ApiClientOptions) {}

  get<T>(path: string, query?: Query): Promise<T> {
    return this.request<T>('GET', path, undefined, query);
  }

  post<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>('POST', path, body ?? {});
  }

  put<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>('PUT', path, body);
  }

  patch<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>('PATCH', path, body);
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown,
    query?: Query,
    retried = false,
  ): Promise<T> {
    const doFetch = this.options.fetchImpl ?? fetch;
    const idToken = await this.options.getIdToken();
    const session = this.options.getSessionToken();
    const headers: Record<string, string> = { Accept: 'application/json' };
    if (idToken) headers.Authorization = `Bearer ${idToken}`;
    if (session) headers['X-Admin-Session'] = session;
    if (body !== undefined) headers['Content-Type'] = 'application/json';

    let response: Response;
    try {
      response = await doFetch(buildUrl(this.options.baseUrl, path, query), {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        credentials: 'omit',
        cache: 'no-store',
      });
    } catch {
      throw new ApiError(0, errorMessage(0, null), undefined, {});
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
    if (response.ok) return parsed as T;

    const errorBody = (parsed ?? {}) as ApiErrorBody;
    const error = new ApiError(
      response.status,
      errorMessage(response.status, errorBody),
      typeof errorBody.code === 'string' ? errorBody.code : undefined,
      errorBody,
    );
    if (error.needsStepUp && !retried && this.options.onStepUpRequired) {
      if (await this.options.onStepUpRequired()) {
        return this.request<T>(method, path, body, query, true);
      }
    }
    if (error.needsSecondFactor) this.options.onSessionLost?.();
    throw error;
  }
}
