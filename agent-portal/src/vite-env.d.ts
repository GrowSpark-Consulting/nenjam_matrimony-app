/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Base URL of the Nenjam API. Empty → the in-browser mock API. */
  readonly VITE_API_BASE_URL?: string;
  /** "true" forces the mock API. */
  readonly VITE_USE_MOCKS?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
