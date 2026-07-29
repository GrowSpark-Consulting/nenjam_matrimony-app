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
  logLevel: process.env.LOG_LEVEL ?? 'info',
  fallback: {
    enabled: (process.env.FALLBACK_ENABLED ?? 'true') !== 'false',
    ageRelaxStep1: parseInt(process.env.AGE_RELAX_STEP_1 ?? '2', 10),
    ageRelaxStep2: parseInt(process.env.AGE_RELAX_STEP_2 ?? '5', 10),
    maxTier: parseInt(process.env.MAX_FALLBACK_TIER ?? '10', 10),
  },
});
