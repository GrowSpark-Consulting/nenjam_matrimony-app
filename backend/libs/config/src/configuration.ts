export interface AppConfig {
  nodeEnv: string;
  port: number;
  websocketPort: number;
  database: {
    host: string;
    port: number;
    username: string;
    password: string;
    name: string;
    /** Full connection string. When set (e.g. a shared Neon URL) it takes
     *  precedence over the individual host/port/... fields and carries its own
     *  SSL mode. Lets every teammate point at one shared DB by setting a single
     *  DATABASE_URL, with the discrete fields kept as a local-Postgres fallback. */
    url?: string;
  };
  redis: {
    host: string;
    port: number;
    password?: string;
    username?: string;
    db?: number;
    /** Full connection string (e.g. Redis Cloud) — redis:// or rediss://
     *  (TLS auto-detected from the scheme by ioredis). When set, takes
     *  precedence over the discrete fields below, mirroring DATABASE_URL's
     *  precedence over the discrete DATABASE_* fields. */
    url?: string;
  };
  elasticsearch: {
    node: string;
    /** Basic Auth for a secured cluster (e.g. local dev with security
     *  enabled). Left unset, the client connects without auth. */
    username?: string;
    password?: string;
  };
  smtp: {
    host: string;
    port: number;
    user: string;
    password: string;
  };
  jwt: {
    secret: string;
  };
  cors: {
    /** Explicit allowlist of origins permitted to call the API cross-origin,
     *  parsed from the comma-separated CORS_ORIGINS. Empty means "no override" —
     *  main.ts then falls back to environment-based defaults (permissive in
     *  development, closed in production) rather than a hardcoded domain. */
    origins: string[];
  };
  mail: {
    /** Selects the EmailProvider binding at module init. Adding a provider
     *  means adding a case here — no business-logic change. */
    provider: 'resend' | 'noop';
    /** RFC 5322 From header, e.g. `Nenjam Matrimony <no-reply@example.com>`. */
    from: string;
    replyTo?: string;
    /** Absent -> MailModule binds NoopEmailProvider and only logs. */
    resendApiKey?: string;
    /** Base URL for CTA links rendered into templates. */
    appUrl: string;
    /** Shown in every template footer. */
    supportEmail: string;
    /** Absolute URL; templates fall back to a text wordmark when unset. */
    logoUrl?: string;
  };
  firebase: {
    projectId?: string;
    clientEmail?: string;
    privateKey?: string;
  };
  storage: {
    region?: string;
    accessKeyId?: string;
    secretAccessKey?: string;
    bucket?: string;
  };
  /** Face verification (AWS Rekognition Face Liveness + CompareFaces).
   *  Deliberately a separate AWS identity from `storage`: these credentials
   *  belong to the face-verification backend IAM user only, and the S3 keys are
   *  never reused here or handed to a client. Off unless explicitly enabled, and
   *  inert (endpoints answer 503) until every AWS value below is supplied. */
  faceVerification: {
    enabled: boolean;
    region: string;
    accessKeyId?: string;
    secretAccessKey?: string;
    /** Role the backend assumes to mint the device's short-lived credentials. */
    clientRoleArn?: string;
    credentialsTtlSeconds: number;
    /** Minimum AWS liveness confidence (0-100) to accept a session. */
    minLivenessConfidence: number;
    /** Minimum CompareFaces similarity (0-100) to accept a match. */
    minMatchSimilarity: number;
    /** Rolling 24-hour cap on paid attempts per member. */
    maxAttemptsPerDay: number;
    /** Cap on paid attempts across all members per UTC day — a spend breaker. */
    globalDailyCap: number;
  };
  logLevel: string;
  /** Progressive Discover-feed fallback (see ProgressiveFallbackStrategy) —
   *  how far and by how much the recommendation engine widens a search that
   *  returns zero strict matches. */
  fallback: {
    enabled: boolean;
    ageRelaxStep1: number;
    ageRelaxStep2: number;
    maxTier: number;
  };
  /** Psychology as an optional Discover ranking signal (see
   *  PsychologyMatchContextService). It can never fail a Discover request;
   *  these only bound how much of a request it may spend. */
  psychology: {
    /** Kill switch. When false Discover scores exactly as it did before the
     *  psychology signal existed, and no psychology query is issued. */
    enabled: boolean;
    /** Wall-clock budget per psychology lookup phase, in ms. Past it the
     *  request carries on without psychology. */
    timeoutMs: number;
    /** Days a member must wait before changing their quiz answers again. The
     *  first submission is never delayed, nor is a retake of answers that have
     *  gone stale. 0 disables the cooldown. Bounds how fast one member can
     *  probe another's answers by re-answering and watching the feed. */
    retakeCooldownDays: number;
  };
  /** Membership plans (see docs/membership/README.md). */
  membership: {
    /** How plan limits are applied:
     *  - `off`: no membership check runs; behaviour is exactly pre-membership.
     *  - `shadow`: plans are resolved and usage recorded; anything that would
     *    be denied is logged and ALLOWED. The default: safe to deploy before
     *    checkout is live, and it measures who would hit which limit.
     *  - `enforce`: limits and paid features are enforced (403). */
    enforcementMode: MembershipEnforcementMode;
  };
  /** Razorpay. All optional — absent, the app boots and the checkout and
   *  webhook routes answer 503, mirroring face verification. */
  razorpay: {
    keyId?: string;
    keySecret?: string;
    webhookSecret?: string;
  };
}

export type MembershipEnforcementMode = 'off' | 'shadow' | 'enforce';

const ENFORCEMENT_MODES: readonly MembershipEnforcementMode[] = [
  'off',
  'shadow',
  'enforce',
];

/** MEMBERSHIP_ENFORCEMENT_MODE, defaulting to `shadow` — never to `enforce`,
 *  so a missing or mistyped value can't start denying members. */
function enforcementModeOf(raw: string | undefined): MembershipEnforcementMode {
  const value = raw?.trim().toLowerCase();
  return ENFORCEMENT_MODES.find((mode) => mode === value) ?? 'shadow';
}

/** A numeric env var, or `fallback` when it is absent/blank/not a number. */
function numberOr(raw: string | undefined, fallback: number): number {
  if (raw == null || raw.trim() === '') return fallback;
  const n = Number(raw);
  return Number.isFinite(n) ? n : fallback;
}

export default (): AppConfig => ({
  nodeEnv: process.env.NODE_ENV ?? 'development',
  port: parseInt(process.env.PORT ?? '3000', 10),
  websocketPort: parseInt(process.env.WEBSOCKET_PORT ?? '3001', 10),
  database: {
    host: process.env.DATABASE_HOST ?? 'localhost',
    port: parseInt(process.env.DATABASE_PORT ?? '5432', 10),
    username: process.env.DATABASE_USER ?? 'postgres',
    password: process.env.DATABASE_PASSWORD ?? '',
    name: process.env.DATABASE_NAME ?? 'app',
    url: process.env.DATABASE_URL?.trim() || undefined,
  },
  redis: {
    host: process.env.REDIS_HOST ?? 'localhost',
    port: parseInt(process.env.REDIS_PORT ?? '6379', 10),
    password: process.env.REDIS_PASSWORD || undefined,
    username: process.env.REDIS_USERNAME || undefined,
    db: process.env.REDIS_DB ? parseInt(process.env.REDIS_DB, 10) : undefined,
    url: process.env.REDIS_URL?.trim() || undefined,
  },
  elasticsearch: {
    node: process.env.ELASTICSEARCH_NODE ?? 'http://localhost:9200',
    username: process.env.ELASTICSEARCH_USERNAME || undefined,
    password: process.env.ELASTICSEARCH_PASSWORD || undefined,
  },
  smtp: {
    host: process.env.SMTP_HOST ?? 'localhost',
    port: parseInt(process.env.SMTP_PORT ?? '1025', 10),
    user: process.env.SMTP_USER ?? '',
    password: process.env.SMTP_PASSWORD ?? '',
  },
  jwt: {
    secret: process.env.JWT_SECRET ?? '',
  },
  cors: {
    origins: (process.env.CORS_ORIGINS ?? '')
      .split(',')
      .map((origin) => origin.trim())
      .filter(Boolean),
  },
  // Email. Mirrors the Firebase/AWS treatment above: absent credentials must
  // not stop the app booting. With no RESEND_API_KEY the MailModule binds a
  // no-op provider that renders and logs but never calls out — so local dev
  // and CI exercise the full queue -> worker -> template path for free.
  mail: {
    provider: process.env.RESEND_API_KEY?.trim() ? 'resend' : 'noop',
    from: process.env.MAIL_FROM ?? 'Nenjam Matrimony <onboarding@resend.dev>',
    replyTo: process.env.MAIL_REPLY_TO || undefined,
    resendApiKey: process.env.RESEND_API_KEY?.trim() || undefined,
    appUrl: process.env.APP_WEB_URL ?? 'https://nenjammatrimony.com',
    supportEmail:
      process.env.MAIL_SUPPORT_EMAIL ?? 'support@nenjammatrimony.com',
    logoUrl: process.env.MAIL_LOGO_URL || undefined,
  },
  firebase: {
    projectId: process.env.FIREBASE_PROJECT_ID || undefined,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL || undefined,
    // Env files commonly store the PEM key with literal "\n" sequences
    // instead of real newlines — Firebase Admin's cert() requires real ones.
    privateKey:
      process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n') || undefined,
  },
  // AWS S3 (profile photos + verification documents). Left unset, the app
  // still boots — only the photo-upload endpoints require these, and
  // S3Service throws a clear error if a request reaches it unconfigured.
  storage: {
    region: process.env.AWS_REGION || undefined,
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || undefined,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || undefined,
    bucket: process.env.AWS_S3_BUCKET_NAME || undefined,
  },
  // Face verification. Mirrors the Firebase/AWS/Resend treatment: absent
  // credentials never stop the app booting — FaceVerificationService answers
  // 503 NOT_AVAILABLE instead. Numeric defaults match validation.ts.
  faceVerification: {
    enabled: process.env.FACE_VERIFICATION_ENABLED?.trim() === 'true',
    region: process.env.FACE_VERIFICATION_AWS_REGION?.trim() || 'ap-south-1',
    accessKeyId:
      process.env.FACE_VERIFICATION_AWS_ACCESS_KEY_ID?.trim() || undefined,
    secretAccessKey:
      process.env.FACE_VERIFICATION_AWS_SECRET_ACCESS_KEY?.trim() || undefined,
    clientRoleArn:
      process.env.FACE_LIVENESS_CLIENT_ROLE_ARN?.trim() || undefined,
    credentialsTtlSeconds: numberOr(
      process.env.FACE_LIVENESS_CREDENTIALS_TTL_SECONDS,
      900,
    ),
    minLivenessConfidence: numberOr(
      process.env.FACE_LIVENESS_MIN_CONFIDENCE,
      90,
    ),
    minMatchSimilarity: numberOr(process.env.FACE_MATCH_MIN_SIMILARITY, 90),
    maxAttemptsPerDay: numberOr(
      process.env.FACE_VERIFICATION_MAX_ATTEMPTS_PER_DAY,
      3,
    ),
    globalDailyCap: numberOr(
      process.env.FACE_VERIFICATION_GLOBAL_DAILY_CAP,
      500,
    ),
  },
  logLevel: process.env.LOG_LEVEL ?? 'info',
  fallback: {
    enabled: (process.env.FALLBACK_ENABLED ?? 'true') !== 'false',
    ageRelaxStep1: parseInt(process.env.AGE_RELAX_STEP_1 ?? '2', 10),
    ageRelaxStep2: parseInt(process.env.AGE_RELAX_STEP_2 ?? '5', 10),
    maxTier: parseInt(process.env.MAX_FALLBACK_TIER ?? '10', 10),
  },
  psychology: {
    enabled: (process.env.PSYCHOLOGY_MATCHING_ENABLED ?? 'true') !== 'false',
    timeoutMs: numberOr(process.env.PSYCHOLOGY_TIMEOUT_MS, 800),
    retakeCooldownDays: numberOr(
      process.env.PSYCHOLOGY_RETAKE_COOLDOWN_DAYS,
      7,
    ),
  },
  membership: {
    enforcementMode: enforcementModeOf(process.env.MEMBERSHIP_ENFORCEMENT_MODE),
  },
  razorpay: {
    keyId: process.env.RAZORPAY_KEY_ID?.trim() || undefined,
    keySecret: process.env.RAZORPAY_KEY_SECRET?.trim() || undefined,
    webhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET?.trim() || undefined,
  },
});
