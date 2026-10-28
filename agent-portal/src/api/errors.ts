import type { AgentStatus } from './types';

/**
 * A failed API call. Branch on `code`, never on `message` — the contract's
 * rule. `message` is the server's own text (a validation list is joined) and
 * is what the portal shows. A code the contract doesn't list yet (for
 * example the exact 409 codes on `POST /agent/application`, still to be
 * confirmed) is kept as-is, never guessed.
 */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string | null;
  readonly agentStatus: AgentStatus | null;
  /** Seconds, from the `Retry-After` header on a 429. */
  readonly retryAfterSeconds: number | null;

  constructor(
    status: number,
    message: string,
    options: {
      code?: string | null;
      agentStatus?: AgentStatus | null;
      retryAfterSeconds?: number | null;
    } = {},
  ) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = options.code ?? null;
    this.agentStatus = options.agentStatus ?? null;
    this.retryAfterSeconds = options.retryAfterSeconds ?? null;
  }

  /** The request never reached the server (offline, DNS, CORS, timeout). */
  static network(): ApiError {
    return new ApiError(0, 'Could not reach the server.', { code: null });
  }

  get isNetworkError(): boolean {
    return this.status === 0;
  }

  get isServerError(): boolean {
    return this.status >= 500;
  }

  get isRateLimited(): boolean {
    return this.status === 429 || this.code === 'RATE_LIMITED';
  }
}

/** Builds an ApiError from a non-2xx response and its parsed body. */
export function toApiError(
  status: number,
  body: unknown,
  retryAfterHeader: string | null,
): ApiError {
  const obj = body && typeof body === 'object' ? (body as Record<string, unknown>) : {};
  const raw = obj.message;
  const message =
    typeof raw === 'string' && raw
      ? raw
      : Array.isArray(raw) && raw.length > 0
        ? raw.filter((m) => typeof m === 'string').join(', ')
        : `Request failed (${status}).`;
  const code = typeof obj.code === 'string' && obj.code ? obj.code : null;
  const agentStatus =
    typeof obj.agentStatus === 'string' ? (obj.agentStatus as AgentStatus) : null;
  const retry = retryAfterHeader === null ? NaN : Number(retryAfterHeader);
  return new ApiError(status, message, {
    code,
    agentStatus,
    retryAfterSeconds: Number.isFinite(retry) && retry > 0 ? Math.ceil(retry) : null,
  });
}
