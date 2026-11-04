import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import type { ApiSetup } from '../api';
import type { StoredSession } from '../api/session';
import type { AgentConfig, AgentProfile, Session } from '../api/types';

interface PortalState extends ApiSetup {
  stored: StoredSession | null;
  /**
   * The agent record; null for an applicant, while signed out, or when
   * `/agent/me` has not succeeded yet. Null never means "no agent exists".
   */
  agent: AgentProfile | null;
  config: AgentConfig | null;
  /** An agent session whose `/agent/me` has not answered (or is being retried). */
  loading: boolean;
  /** `/agent/config` has not answered (or is being retried). */
  configLoading: boolean;
  /**
   * The last `/agent/me` failure, cleared when a later call succeeds. If
   * `agent` is also set it is the last good copy, not a confirmed refresh.
   */
  agentError: unknown;
  /** The last `/agent/config` failure, cleared when a later call succeeds. */
  configError: unknown;
  /** Stores a session from sign-in or application. */
  startSession: (session: Session) => void;
  /** Re-reads `GET /agent/me` and `/agent/config` (e.g. after `AGENT_NOT_ACTIVE`). */
  reloadAgent: () => void;
  /** Retries `GET /agent/me` only; ignored while one is already in flight. */
  retryAgent: () => void;
  /** Retries `GET /agent/config` only; ignored while one is already in flight. */
  retryConfig: () => void;
  signOut: () => Promise<void>;
}

const PortalContext = createContext<PortalState | null>(null);

interface Slot<T> {
  /** The request (tick) this answer belongs to. */
  key: number;
  data: T | null;
  error: unknown;
}

/**
 * One independently loaded, independently failing request.
 *
 * - A failure records its error and keeps the last good `data` (so a retry
 *   that fails shows stale data plus an error, never an empty screen).
 * - A success clears the error.
 * - An answer is only stored if its request is still the latest one
 *   (`alive`), so a stale or unmounted request can never overwrite newer state.
 * - `retry` does nothing while a request is in flight; `refresh` always
 *   starts a new one (the old answer is then ignored).
 */
function useSlot<T>(enabled: boolean, load: () => Promise<T>) {
  const [tick, setTick] = useState(0);
  const [slot, setSlot] = useState<Slot<T> | null>(null);
  const inFlight = useRef(false);

  useEffect(() => {
    if (!enabled) return;
    let alive = true;
    inFlight.current = true;
    load().then(
      (data) => {
        if (!alive) return;
        inFlight.current = false;
        setSlot({ key: tick, data, error: null });
      },
      (error: unknown) => {
        if (!alive) return;
        inFlight.current = false;
        setSlot((prev) => ({ key: tick, data: prev?.data ?? null, error }));
      },
    );
    return () => {
      alive = false;
    };
  }, [enabled, load, tick]);

  const loading = enabled && slot?.key !== tick;
  const refresh = useCallback(() => setTick((t) => t + 1), []);
  const retry = useCallback(() => {
    if (!inFlight.current) setTick((t) => t + 1);
  }, []);
  const reset = useCallback(() => setSlot(null), []);
  return {
    data: slot?.data ?? null,
    // Hidden while a retry is running; the screens show loading instead.
    error: loading ? null : (slot?.error ?? null),
    loading,
    refresh,
    retry,
    reset,
  };
}

export function PortalProvider({ setup, children }: { setup: ApiSetup; children: ReactNode }) {
  const { api, sessions } = setup;
  const [stored, setStored] = useState<StoredSession | null>(() => {
    const s = sessions.get();
    // An expired applicant session can't be refreshed: start over at OTP.
    if (s && s.session.scope === 'APPLICANT' && s.expiresAt <= Date.now()) {
      sessions.clear();
      return null;
    }
    return s;
  });
  // The profile handed back by sign-in/application, shown until /me answers.
  const [seed, setSeed] = useState<AgentProfile | null>(null);

  const isAgent = stored?.session.scope === 'AGENT';
  // `/agent/me` and `/agent/config` are separate slots: one failing never
  // discards the other's answer. A 401 on either already cleared the session
  // (HttpClient); any other failure is recorded, never read as "no agent".
  const me = useSlot<AgentProfile>(isAgent, useCallback(() => api.getMe(), [api]));
  const cfg = useSlot<AgentConfig>(isAgent, useCallback(() => api.getConfig(), [api]));
  const { reset: resetMe, refresh: refreshMe } = me;
  const { reset: resetCfg, refresh: refreshCfg } = cfg;

  useEffect(
    () =>
      sessions.subscribe((s) => {
        setStored(s);
        if (!s) {
          // Signed out (or a 401 cleared the session): drop everything that
          // belonged to that agent so it can never show for the next one.
          setSeed(null);
          resetMe();
          resetCfg();
        }
      }),
    [sessions, resetMe, resetCfg],
  );

  const agent = isAgent ? (me.data ?? seed) : null;
  const config = isAgent ? cfg.data : null;

  const reloadAgent = useCallback(() => {
    refreshMe();
    refreshCfg();
  }, [refreshMe, refreshCfg]);

  const startSession = useCallback(
    (session: Session) => {
      setSeed(session.scope === 'AGENT' ? session.agent : null);
      resetMe();
      resetCfg();
      sessions.set(session);
      reloadAgent();
    },
    [sessions, resetMe, resetCfg, reloadAgent],
  );

  const signOut = useCallback(async () => {
    const current = sessions.get()?.session;
    if (current?.scope === 'AGENT') {
      try {
        await api.logout(current.refreshToken);
      } catch {
        // Signing out locally matters more than revoking remotely.
      }
    }
    sessions.clear();
  }, [api, sessions]);

  const value = useMemo<PortalState>(
    () => ({
      ...setup,
      stored,
      agent,
      config,
      loading: me.loading,
      configLoading: cfg.loading,
      agentError: isAgent ? me.error : null,
      configError: isAgent ? cfg.error : null,
      startSession,
      reloadAgent,
      retryAgent: me.retry,
      retryConfig: cfg.retry,
      signOut,
    }),
    [
      setup,
      stored,
      agent,
      config,
      isAgent,
      me.loading,
      me.error,
      me.retry,
      cfg.loading,
      cfg.error,
      cfg.retry,
      startSession,
      reloadAgent,
      signOut,
    ],
  );
  return <PortalContext.Provider value={value}>{children}</PortalContext.Provider>;
}

// eslint-disable-next-line react-refresh/only-export-components
export function usePortal(): PortalState {
  const ctx = useContext(PortalContext);
  if (!ctx) throw new Error('usePortal must be used inside PortalProvider');
  return ctx;
}
