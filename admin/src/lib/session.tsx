'use client';

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
import {
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut as firebaseSignOut,
} from 'firebase/auth';
import { ApiClient, ApiError } from './api';
import { config, missingConfig } from './config';
import { firebaseAuth } from './firebase';
import type { AdminMe, AdminSession } from './types';

/**
 * Staff sign-in, in two steps, both checked by the API:
 *   1. Firebase email + password (identity),
 *   2. an authenticator code → admin session token (second factor).
 *
 * The session token lives in sessionStorage (this tab only, gone when the tab
 * closes), never in localStorage or a cookie. The API ends sessions after
 * 12 hours or 30 idle minutes; the panel also signs out after 30 idle minutes.
 */
export type Phase =
  | 'unconfigured'
  | 'loading'
  | 'signedOut'
  | 'secondFactor'
  | 'notStaff'
  | 'error'
  | 'ready';

const SESSION_KEY = 'nenjam-admin-session';
const IDLE_LIMIT_MS = 30 * 60 * 1000;

interface SessionValue {
  phase: Phase;
  me: AdminMe | null;
  /** Email of the Firebase account currently signed in. */
  email: string | null;
  /** A one-off message for the next screen (e.g. "session ended"). */
  notice: string | null;
  error: string | null;
  api: ApiClient;
  signIn(email: string, password: string): Promise<void>;
  verifyCode(code: string): Promise<void>;
  startEnrollment(
    enrollmentCode: string,
  ): Promise<{ secret: string; otpauthUri: string }>;
  confirmEnrollment(enrollmentCode: string, code: string): Promise<void>;
  signOut(notice?: string): Promise<void>;
  retry(): void;
  /** Step-up prompt state, rendered by <StepUpDialog />. */
  stepUpOpen: boolean;
  resolveStepUp(confirmed: boolean): void;
}

const SessionContext = createContext<SessionValue | null>(null);

function readToken(): string | null {
  try {
    return window.sessionStorage.getItem(SESSION_KEY);
  } catch {
    return null;
  }
}

function writeToken(token: string | null): void {
  try {
    if (token) window.sessionStorage.setItem(SESSION_KEY, token);
    else window.sessionStorage.removeItem(SESSION_KEY);
  } catch {
    // Storage blocked: the session simply won't survive a reload.
  }
}

export function firebaseErrorMessage(error: unknown): string {
  const code = (error as { code?: string })?.code ?? '';
  if (
    code === 'auth/invalid-credential' ||
    code === 'auth/wrong-password' ||
    code === 'auth/user-not-found' ||
    code === 'auth/invalid-email'
  ) {
    return 'Email or password is incorrect.';
  }
  if (code === 'auth/too-many-requests') {
    return 'Too many attempts. Wait a few minutes and try again.';
  }
  if (code === 'auth/user-disabled') return 'This account is disabled.';
  if (code === 'auth/network-request-failed') {
    return 'Could not reach Firebase. Check your connection.';
  }
  return 'Sign-in failed. Please try again.';
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [phase, setPhase] = useState<Phase>(
    missingConfig.length > 0 ? 'unconfigured' : 'loading',
  );
  const [me, setMe] = useState<AdminMe | null>(null);
  const [email, setEmail] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [stepUpOpen, setStepUpOpen] = useState(false);
  const stepUpResolver = useRef<((ok: boolean) => void) | null>(null);
  const lastActivity = useRef(Date.now());

  const sessionLost = useCallback(() => {
    writeToken(null);
    setMe(null);
    setNotice('Your admin session has ended. Enter a new code from your authenticator app.');
    setPhase('secondFactor');
  }, []);

  const api = useMemo(
    () =>
      new ApiClient({
        baseUrl: config.apiBaseUrl,
        getIdToken: async () => {
          if (missingConfig.length > 0) return null;
          const user = firebaseAuth().currentUser;
          return user ? user.getIdToken() : null;
        },
        getSessionToken: readToken,
        onSessionLost: sessionLost,
        onStepUpRequired: () =>
          new Promise<boolean>((resolve) => {
            stepUpResolver.current = resolve;
            setStepUpOpen(true);
          }),
      }),
    [sessionLost],
  );

  const loadMe = useCallback(async () => {
    try {
      const admin = await api.get<AdminMe>('/admin/me');
      setMe(admin);
      setError(null);
      setPhase('ready');
    } catch (e) {
      if (e instanceof ApiError && e.needsSecondFactor) {
        writeToken(null);
        setPhase('secondFactor');
      } else if (e instanceof ApiError && e.code === 'ADMIN_ACCESS_REQUIRED') {
        writeToken(null);
        setPhase('notStaff');
      } else {
        setError(e instanceof Error ? e.message : 'Something went wrong.');
        setPhase('error');
      }
    }
  }, [api]);

  useEffect(() => {
    if (missingConfig.length > 0) return;
    return onAuthStateChanged(firebaseAuth(), (user) => {
      setEmail(user?.email ?? null);
      if (!user) {
        writeToken(null);
        setMe(null);
        setPhase('signedOut');
        return;
      }
      if (readToken()) void loadMe();
      else setPhase('secondFactor');
    });
  }, [loadMe]);

  const signOut = useCallback(
    async (message?: string) => {
      if (readToken()) {
        await api.post('/admin/auth/logout').catch(() => undefined);
      }
      writeToken(null);
      setMe(null);
      setNotice(message ?? null);
      if (missingConfig.length === 0) {
        await firebaseSignOut(firebaseAuth()).catch(() => undefined);
      }
      setPhase('signedOut');
    },
    [api],
  );

  // Idle sign-out, mirroring the API's 30-minute idle limit.
  useEffect(() => {
    if (phase !== 'ready') return;
    const touch = () => {
      lastActivity.current = Date.now();
    };
    const events = ['mousedown', 'keydown', 'touchstart', 'scroll'] as const;
    events.forEach((name) => window.addEventListener(name, touch, { passive: true }));
    const timer = window.setInterval(() => {
      if (Date.now() - lastActivity.current > IDLE_LIMIT_MS) {
        void signOut('You were signed out after 30 minutes without activity.');
      }
    }, 60_000);
    return () => {
      events.forEach((name) => window.removeEventListener(name, touch));
      window.clearInterval(timer);
    };
  }, [phase, signOut]);

  const value: SessionValue = {
    phase,
    me,
    email,
    notice,
    error,
    api,
    async signIn(emailAddress, password) {
      setNotice(null);
      await signInWithEmailAndPassword(firebaseAuth(), emailAddress.trim(), password);
      // onAuthStateChanged moves the phase on.
    },
    async verifyCode(code) {
      const session = await api.post<AdminSession>('/admin/auth/session', { code });
      writeToken(session.sessionToken);
      setNotice(null);
      lastActivity.current = Date.now();
      await loadMe();
    },
    startEnrollment(enrollmentCode) {
      return api.post('/admin/auth/mfa/enrollment', { enrollmentCode });
    },
    async confirmEnrollment(enrollmentCode, code) {
      const session = await api.post<AdminSession>(
        '/admin/auth/mfa/enrollment/confirm',
        { enrollmentCode, code },
      );
      writeToken(session.sessionToken);
      setNotice(null);
      lastActivity.current = Date.now();
      await loadMe();
    },
    signOut,
    retry() {
      setPhase('loading');
      void loadMe();
    },
    stepUpOpen,
    resolveStepUp(confirmed) {
      setStepUpOpen(false);
      stepUpResolver.current?.(confirmed);
      stepUpResolver.current = null;
    },
  };

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error('useSession must be used inside <SessionProvider>.');
  return value;
}
