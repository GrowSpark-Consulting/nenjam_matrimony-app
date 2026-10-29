import { getApps, initializeApp, type FirebaseApp } from 'firebase/app';
import {
  browserSessionPersistence,
  getAuth,
  setPersistence,
  type Auth,
} from 'firebase/auth';
import { config, missingConfig } from './config';

let auth: Auth | null = null;

/**
 * The Firebase Auth instance (identity only — staff sign in with email and
 * password). Session persistence: closing the browser tab signs the admin
 * out of Firebase too, on top of the API's own 12-hour/30-minute session.
 */
export function firebaseAuth(): Auth {
  if (auth) return auth;
  if (missingConfig.length > 0) {
    throw new Error(`Admin panel is not configured: ${missingConfig.join(', ')}`);
  }
  const app: FirebaseApp = getApps()[0] ?? initializeApp(config.firebase);
  auth = getAuth(app);
  void setPersistence(auth, browserSessionPersistence);
  return auth;
}
