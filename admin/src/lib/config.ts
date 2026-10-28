/**
 * Build-time public configuration (NEXT_PUBLIC_* is inlined into the bundle).
 * Nothing here is a secret. `missing` lists what is not set, so the app can
 * say so instead of failing obscurely.
 */
export const config = {
  apiBaseUrl: (process.env.NEXT_PUBLIC_API_BASE_URL ?? '').replace(/\/+$/, ''),
  firebase: {
    apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY ?? '',
    authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN ?? '',
    projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ?? '',
    appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID ?? '',
  },
};

export const missingConfig: string[] = [
  ['NEXT_PUBLIC_API_BASE_URL', config.apiBaseUrl],
  ['NEXT_PUBLIC_FIREBASE_API_KEY', config.firebase.apiKey],
  ['NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN', config.firebase.authDomain],
  ['NEXT_PUBLIC_FIREBASE_PROJECT_ID', config.firebase.projectId],
  ['NEXT_PUBLIC_FIREBASE_APP_ID', config.firebase.appId],
]
  .filter(([, value]) => !value)
  .map(([name]) => name as string);
