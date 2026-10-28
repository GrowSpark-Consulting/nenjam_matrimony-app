import type { Session } from './types';

/**
 * Where the agent's own tokens live. Completely separate from member
 * (Firebase) authentication: the portal never sees a Firebase token.
 *
 * Stored in localStorage so an agent on a phone stays signed in across tabs.
 * Tokens are only ever sent in the `Authorization` header — never in a URL —
 * and never logged. An applicant session has no refresh token and simply
 * expires.
 *
 * Tabs stay in step: a sign-out or a token refresh in one tab reaches the
 * others through the browser's `storage` event.
 */
export const SESSION_STORAGE_KEY = 'nenjam.agentPortal.session';

export interface StoredSession {
  session: Session;
  /** Epoch ms when the access token expires (from `expiresInSeconds`). */
  expiresAt: number;
}

type Listener = (stored: StoredSession | null) => void;

export class SessionStore {
  private listeners = new Set<Listener>();
  private readonly storage: Storage;
  private readonly now: () => number;

  constructor(
    storage: Storage = window.localStorage,
    now: () => number = Date.now,
    events: Pick<Window, 'addEventListener'> | null = typeof window === 'undefined' ? null : window,
  ) {
    this.storage = storage;
    this.now = now;
    events?.addEventListener('storage', (e: StorageEvent) => {
      if (e.key === SESSION_STORAGE_KEY || e.key === null) this.emit(this.get());
    });
  }

  get(): StoredSession | null {
    const raw = this.storage.getItem(SESSION_STORAGE_KEY);
    if (!raw) return null;
    try {
      return JSON.parse(raw) as StoredSession;
    } catch {
      this.storage.removeItem(SESSION_STORAGE_KEY);
      return null;
    }
  }

  /** Stores a session from the API, using its own `expiresInSeconds`. */
  set(session: Session): StoredSession {
    const stored: StoredSession = {
      session,
      expiresAt: this.now() + session.expiresInSeconds * 1000,
    };
    this.storage.setItem(SESSION_STORAGE_KEY, JSON.stringify(stored));
    this.emit(stored);
    return stored;
  }

  clear(): void {
    this.storage.removeItem(SESSION_STORAGE_KEY);
    this.emit(null);
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(stored: StoredSession | null) {
    for (const l of this.listeners) l(stored);
  }
}
