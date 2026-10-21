/**
 * One origin policy for the whole API, so the HTTP layer and Socket.IO cannot
 * drift apart.
 *
 * - `CORS_ORIGINS` set  -> exactly those origins, in every environment.
 * - unset, development  -> any origin (local tools and dev servers).
 * - unset, otherwise    -> no cross-origin browser access (fail closed).
 *
 * Only *browsers* send an `Origin` header; native mobile clients and server
 * tools do not, and they authenticate with a Firebase ID token regardless, so
 * a request with no `Origin` is not a cross-origin browser request and is not
 * judged here.
 */
export interface OriginPolicy {
  /** Parsed `CORS_ORIGINS`. */
  allowedOrigins: readonly string[];
  isDevelopment: boolean;
}

/** The value for the `origin` option of Express `cors` / Socket.IO `cors`. */
export function corsOriginOption(policy: OriginPolicy): string[] | boolean {
  return policy.allowedOrigins.length > 0
    ? [...policy.allowedOrigins]
    : policy.isDevelopment;
}

/** Whether a request carrying [origin] may reach the API from a browser. */
export function isOriginAllowed(
  origin: string | undefined,
  policy: OriginPolicy,
): boolean {
  if (!origin) return true;
  if (policy.allowedOrigins.length > 0) {
    return policy.allowedOrigins.includes(origin);
  }
  return policy.isDevelopment;
}
