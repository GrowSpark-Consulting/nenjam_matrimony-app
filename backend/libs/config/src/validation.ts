import * as Joi from 'joi';

export const validationSchema = Joi.object({
  NODE_ENV: Joi.string()
    .valid('development', 'production', 'test', 'staging')
    .default('development'),
  PORT: Joi.number().port().default(3000),
  WEBSOCKET_PORT: Joi.number().port().default(3001),

  // Either a full DATABASE_URL (shared Neon/managed Postgres, preferred — the
  // app uses it verbatim, SSL included) OR the discrete fields below (local
  // Postgres). The individual fields are optional so a teammate can point at
  // the shared DB by setting only DATABASE_URL. `PrismaService` validates real
  // connectivity at boot, so a config with neither fails fast with a clear error.
  DATABASE_URL: Joi.string().optional(),
  DATABASE_HOST: Joi.string().optional(),
  DATABASE_PORT: Joi.number().port().optional(),
  DATABASE_USER: Joi.string().optional(),
  DATABASE_PASSWORD: Joi.string().allow('').optional(),
  DATABASE_NAME: Joi.string().optional(),

  // Either a single REDIS_URL (managed Redis, e.g. Redis Cloud — redis:// or
  // rediss://, preferred) OR the discrete fields below (local Redis/Memurai).
  // The discrete fields are optional so a teammate can point at a managed
  // instance by setting only REDIS_URL, exactly like DATABASE_URL above.
  // .empty('') treats a blank value the same as an absent one (rather than a
  // validation error) — REDIS_HOST/PORT/DB are typically left blank on
  // purpose once REDIS_URL is in use.
  REDIS_URL: Joi.string().allow('').optional(),
  REDIS_HOST: Joi.string().empty('').optional(),
  REDIS_PORT: Joi.number().port().empty('').optional(),
  REDIS_USERNAME: Joi.string().allow('').optional(),
  REDIS_PASSWORD: Joi.string().allow('').optional(),
  REDIS_DB: Joi.number().integer().min(0).empty('').optional(),

  ELASTICSEARCH_NODE: Joi.string().uri().required(),
  // Optional: Basic Auth for a secured cluster (e.g. local dev with security
  // enabled). Left unset, the client connects without auth.
  ELASTICSEARCH_USERNAME: Joi.string().allow('').optional(),
  ELASTICSEARCH_PASSWORD: Joi.string().allow('').optional(),

  SMTP_HOST: Joi.string().required(),
  SMTP_PORT: Joi.number().port().required(),
  SMTP_USER: Joi.string().allow('').optional(),
  SMTP_PASSWORD: Joi.string().allow('').optional(),

  JWT_SECRET: Joi.string().min(16).required(),

  // Explicit CORS allowlist for the API's HTTP layer (apps/api/src/main.ts).
  // Comma-separated origins, e.g. "https://app.example.com,https://example.com".
  // Optional: left unset, main.ts falls back to reflecting the request origin in
  // development and rejecting cross-origin requests in production — never a
  // hardcoded domain either way.
  CORS_ORIGINS: Joi.string().allow('').optional(),

  // Email. Optional by design, matching Firebase/AWS below: without
  // RESEND_API_KEY the app still boots and MailModule binds a no-op provider
  // that renders + logs instead of sending. Making it required would block
  // every developer and every CI run on a third-party secret.
  //
  // The key format is still validated when present, so a truncated or
  // wrong-provider paste fails at boot with a clear message rather than as a
  // 401 from Resend on the first real send, hours later, inside a worker.
  RESEND_API_KEY: Joi.string()
    .pattern(/^re_[A-Za-z0-9_-]{10,}$/)
    .allow('')
    .optional()
    .messages({
      'string.pattern.base':
        'RESEND_API_KEY must look like "re_xxxxxxxx" (copy it from https://resend.com/api-keys).',
    }),
  // RFC 5322: either `local@domain` or `Display Name <local@domain>`. Resend
  // rejects anything else, and it rejects it per-send rather than at startup.
  MAIL_FROM: Joi.string()
    .pattern(
      /^(.*<\s*[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+\s*>|[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+)$/,
    )
    .optional()
    .messages({
      'string.pattern.base':
        'MAIL_FROM must be "user@domain.com" or "Display Name <user@domain.com>".',
    }),
  MAIL_REPLY_TO: Joi.string().email().allow('').optional(),
  MAIL_SUPPORT_EMAIL: Joi.string().email().allow('').optional(),
  MAIL_LOGO_URL: Joi.string().uri().allow('').optional(),
  APP_WEB_URL: Joi.string().uri().allow('').optional(),

  // Optional: Firebase Admin SDK service-account credentials, used by
  // FirebaseAuthGuard to verify client ID tokens. Left unset, the app still
  // boots (other modules don't need Firebase); any request hitting a
  // Firebase-guarded endpoint will get a clear 500 explaining it's missing.
  FIREBASE_PROJECT_ID: Joi.string().allow('').optional(),
  FIREBASE_CLIENT_EMAIL: Joi.string().allow('').optional(),
  FIREBASE_PRIVATE_KEY: Joi.string().allow('').optional(),

  // Optional: AWS S3 credentials for profile-photo storage. Left unset, the
  // app still boots; only the photo-upload endpoints need them, and
  // S3Service returns a clear error if a request reaches it unconfigured.
  AWS_REGION: Joi.string().allow('').optional(),
  AWS_ACCESS_KEY_ID: Joi.string().allow('').optional(),
  AWS_SECRET_ACCESS_KEY: Joi.string().allow('').optional(),
  AWS_S3_BUCKET_NAME: Joi.string().allow('').optional(),

  // Optional: face verification (AWS Rekognition Face Liveness +
  // CompareFaces). Off by default, and the app boots with every value absent —
  // the endpoints answer 503 until enabled AND fully configured. The key pair
  // belongs to the dedicated face-verification backend IAM identity, never the
  // S3 credentials above. Thresholds/caps are range-checked so a typo fails at
  // boot instead of silently verifying everyone (or no one).
  FACE_VERIFICATION_ENABLED: Joi.boolean().default(false),
  FACE_VERIFICATION_AWS_REGION: Joi.string()
    .pattern(/^[a-z]{2}(-[a-z]+)+-\d$/)
    .allow('')
    .optional()
    .messages({
      'string.pattern.base':
        'FACE_VERIFICATION_AWS_REGION must be an AWS region code, e.g. ap-south-1.',
    }),
  FACE_VERIFICATION_AWS_ACCESS_KEY_ID: Joi.string().allow('').optional(),
  FACE_VERIFICATION_AWS_SECRET_ACCESS_KEY: Joi.string().allow('').optional(),
  FACE_LIVENESS_CLIENT_ROLE_ARN: Joi.string()
    .pattern(/^arn:aws[a-z-]*:iam::\d{12}:role\/[\w+=,.@/-]+$/)
    .allow('')
    .optional()
    .messages({
      'string.pattern.base':
        'FACE_LIVENESS_CLIENT_ROLE_ARN must be an IAM role ARN, e.g. arn:aws:iam::123456789012:role/nenjam-face-liveness-client.',
    }),
  // STS AssumeRole accepts 900-43200s; the device only needs minutes (a
  // liveness session itself expires after 3), so cap well below that.
  FACE_LIVENESS_CREDENTIALS_TTL_SECONDS: Joi.number()
    .integer()
    .min(900)
    .max(3600)
    .default(900),
  FACE_LIVENESS_MIN_CONFIDENCE: Joi.number().min(0).max(100).default(90),
  FACE_MATCH_MIN_SIMILARITY: Joi.number().min(0).max(100).default(90),
  FACE_VERIFICATION_MAX_ATTEMPTS_PER_DAY: Joi.number()
    .integer()
    .min(1)
    .max(20)
    .default(3),
  FACE_VERIFICATION_GLOBAL_DAILY_CAP: Joi.number()
    .integer()
    .min(1)
    .default(500),

  LOG_LEVEL: Joi.string()
    .valid('error', 'warn', 'info', 'debug', 'verbose')
    .default('info'),

  // Progressive Discover-feed fallback (ProgressiveFallbackStrategy). All
  // optional with sane defaults — ops can tune/disable without a code change.
  FALLBACK_ENABLED: Joi.boolean().default(true),
  AGE_RELAX_STEP_1: Joi.number().integer().min(0).default(2),
  AGE_RELAX_STEP_2: Joi.number().integer().min(0).default(5),
  MAX_FALLBACK_TIER: Joi.number().integer().min(1).max(10).default(10),

  // Psychology as an optional Discover ranking signal. Both optional; the
  // timeout is bounded so a typo can neither disable the budget (0) nor let it
  // exceed the client's own request timeout.
  PSYCHOLOGY_MATCHING_ENABLED: Joi.boolean().default(true),
  PSYCHOLOGY_TIMEOUT_MS: Joi.number().integer().min(50).max(5000).default(800),
  // Days before a member may change their quiz answers again (0 = no limit).
  PSYCHOLOGY_RETAKE_COOLDOWN_DAYS: Joi.number()
    .integer()
    .min(0)
    .max(365)
    .default(7),
}).unknown(true);
