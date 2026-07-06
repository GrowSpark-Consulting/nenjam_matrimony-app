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
  logLevel: process.env.LOG_LEVEL ?? 'info',
});
