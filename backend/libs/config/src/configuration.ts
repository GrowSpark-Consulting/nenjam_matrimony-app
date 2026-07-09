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
  };
  redis: {
    host: string;
    port: number;
    password?: string;
  };
  elasticsearch: {
  node: string;
  username: string;
  password: string;
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
    projectId: string;
    clientEmail: string;
    privateKey: string;
  };
  logLevel: string;
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
  },
  redis: {
    host: process.env.REDIS_HOST ?? 'localhost',
    port: parseInt(process.env.REDIS_PORT ?? '6379', 10),
    password: process.env.REDIS_PASSWORD || undefined,
  },
  elasticsearch: {
  node: process.env.ELASTICSEARCH_NODE ?? 'http://localhost:9200',
  username: process.env.ELASTICSEARCH_USERNAME ?? '',
  password: process.env.ELASTICSEARCH_PASSWORD ?? '',
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
    projectId: process.env.FIREBASE_PROJECT_ID ?? '',
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL ?? '',
    // Env vars can't hold real newlines, so the PEM key is stored with
    // literal "\n" sequences and decoded back into a real multi-line key here.
    privateKey: (process.env.FIREBASE_PRIVATE_KEY ?? '').replace(/\\n/g, '\n'),
  },
  logLevel: process.env.LOG_LEVEL ?? 'info',
});
