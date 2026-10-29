import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import type { ApiSetup } from '../api';
import type { StoredSession } from '../api/session';
import type { AgentConfig, AgentProfile, Session } from '../api/types';

interface PortalState extends ApiSetup {
  stored: StoredSession | null;
  /** The agent record; null for an applicant or while signed out. */
  agent: AgentProfile | null;
  config: AgentConfig | null;
  /** An agent session whose `/agent/me` hasn't answered yet. */
  loading: boolean;
  /** Stores a session from sign-in or application. */
  startSession: (session: Session) => void;
  /** Re-reads `GET /agent/me` and `/agent/config` (e.g. after `AGENT_NOT_ACTIVE`). */
  reloadAgent: () => void;
  signOut: () => Promise<void>;
}

const PortalContext = createContext<PortalState | null>(null);

interface Loaded {
  key: string;
  agent: AgentProfile | null;
  config: AgentConfig | null;
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
  const [tick, setTick] = useState(0);
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  // The profile handed back by sign-in/application, shown until /me answers.
  const [seed, setSeed] = useState<AgentProfile | null>(null);

  useEffect(() => sessions.subscribe(setStored), [sessions]);

  const isAgent = stored?.session.scope === 'AGENT';
  const key = isAgent ? `agent:${tick}` : 'none';

  useEffect(() => {
    if (!isAgent) return;
    let alive = true;
    Promise.all([api.getMe(), api.getConfig()]).then(
      ([agent, config]) => alive && setLoaded({ key, agent, config }),
      // A 401 already cleared the session (HttpClient). Anything else leaves
      // what we had; the pages show their own errors.
      () => alive && setLoaded((prev) => ({ key, agent: prev?.agent ?? null, config: prev?.config ?? null })),
    );
    return () => {
      alive = false;
    };
  }, [api, isAgent, key]);

  const current = loaded?.key === key ? loaded : null;
  const agent = isAgent ? (current?.agent ?? seed) : null;
  const config = isAgent ? (current?.config ?? null) : null;
  const loading = isAgent && current === null;

  const startSession = useCallback(
    (session: Session) => {
      setSeed(session.scope === 'AGENT' ? session.agent : null);
      sessions.set(session);
      setTick((t) => t + 1);
    },
    [sessions],
  );

  const reloadAgent = useCallback(() => setTick((t) => t + 1), []);

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
    setSeed(null);
    setLoaded(null);
  }, [api, sessions]);

  const value = useMemo<PortalState>(
    () => ({ ...setup, stored, agent, config, loading, startSession, reloadAgent, signOut }),
    [setup, stored, agent, config, loading, startSession, reloadAgent, signOut],
  );
  return <PortalContext.Provider value={value}>{children}</PortalContext.Provider>;
}

// eslint-disable-next-line react-refresh/only-export-components
export function usePortal(): PortalState {
  const ctx = useContext(PortalContext);
  if (!ctx) throw new Error('usePortal must be used inside PortalProvider');
  return ctx;
}
