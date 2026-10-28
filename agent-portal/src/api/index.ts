import type { AgentApi } from './agentApi';
import { HttpAgentApi } from './agentApi';
import { HttpClient } from './http';
import { SessionStore } from './session';

export interface ApiSetup {
  api: AgentApi;
  sessions: SessionStore;
  /** True only for the in-browser mock, which a production build never has. */
  usingMocks: boolean;
}

export type ApiConfig =
  | { mode: 'live'; baseUrl: string }
  | { mode: 'mock' }
  | { mode: 'invalid'; reason: string };

export interface PortalEnv {
  VITE_API_BASE_URL?: string;
  VITE_USE_MOCKS?: string;
  DEV?: boolean;
}

const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1']);

/**
 * Decides which API the portal talks to. There is NO fallback:
 *
 * - The mock API is used only when explicitly asked for (`VITE_USE_MOCKS=true`)
 *   in a development build. A production build refuses it.
 * - Otherwise `VITE_API_BASE_URL` must be a valid absolute URL: `https:`
 *   always, or `http:` to localhost in development only. A missing or invalid
 *   URL is reported as a configuration error, never silently replaced.
 */
export function resolveApiConfig(env: PortalEnv): ApiConfig {
  if (env.VITE_USE_MOCKS === 'true') {
    return env.DEV
      ? { mode: 'mock' }
      : { mode: 'invalid', reason: 'Mock data cannot be used in a production build.' };
  }
  const raw = (env.VITE_API_BASE_URL ?? '').trim();
  if (!raw) return { mode: 'invalid', reason: 'VITE_API_BASE_URL is not set.' };
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return { mode: 'invalid', reason: 'VITE_API_BASE_URL is not a valid URL.' };
  }
  const devLocal = !!env.DEV && url.protocol === 'http:' && LOCAL_HOSTS.has(url.hostname);
  if (url.protocol !== 'https:' && !devLocal) {
    return { mode: 'invalid', reason: 'VITE_API_BASE_URL must use https.' };
  }
  if (url.search || url.hash || url.username || url.password) {
    return { mode: 'invalid', reason: 'VITE_API_BASE_URL must be a plain base URL.' };
  }
  return { mode: 'live', baseUrl: url.toString().replace(/\/+$/, '') };
}

/** Builds the API for a resolved, valid configuration. */
export async function createApi(
  config: Exclude<ApiConfig, { mode: 'invalid' }>,
): Promise<ApiSetup> {
  const sessions = new SessionStore();
  // `import.meta.env.DEV` is a build-time constant: in a production build this
  // branch is removed, so the mock module is not even shipped.
  if (import.meta.env.DEV && config.mode === 'mock') {
    const { MockAgentApi } = await import('./mockAgentApi');
    return { api: new MockAgentApi(sessions), sessions, usingMocks: true };
  }
  if (config.mode !== 'live') throw new Error('Mock API is not available in this build.');
  return {
    api: new HttpAgentApi(new HttpClient(config.baseUrl, sessions)),
    sessions,
    usingMocks: false,
  };
}
