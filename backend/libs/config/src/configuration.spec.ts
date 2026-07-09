import configuration from './configuration';

describe('configuration', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    process.env = { ...originalEnv };
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it('applies sane defaults when optional env vars are absent', () => {
    delete process.env.PORT;
    delete process.env.WEBSOCKET_PORT;
    delete process.env.NODE_ENV;
    delete process.env.LOG_LEVEL;

    const config = configuration();

    expect(config.nodeEnv).toBe('development');
    expect(config.port).toBe(3000);
    expect(config.websocketPort).toBe(3001);
    expect(config.logLevel).toBe('info');
  });

  it('maps flat env vars into the nested config shape', () => {
    process.env.DATABASE_HOST = 'db.internal';
    process.env.DATABASE_PORT = '5433';
    process.env.DATABASE_USER = 'app_user';
    process.env.DATABASE_PASSWORD = 'secret';
    process.env.DATABASE_NAME = 'app_db';
    process.env.REDIS_HOST = 'redis.internal';
    process.env.REDIS_PORT = '6380';
    process.env.ELASTICSEARCH_NODE = 'http://es.internal:9200';
    process.env.SMTP_HOST = 'smtp.internal';
    process.env.SMTP_PORT = '2525';
    process.env.JWT_SECRET = 'a-very-long-secret-value';

    const config = configuration();

    expect(config.database).toEqual({
      host: 'db.internal',
      port: 5433,
      username: 'app_user',
      password: 'secret',
      name: 'app_db',
    });
    expect(config.redis).toEqual({ host: 'redis.internal', port: 6380 });
    expect(config.elasticsearch).toEqual({ node: 'http://es.internal:9200' });
    expect(config.smtp.host).toBe('smtp.internal');
    expect(config.smtp.port).toBe(2525);
    expect(config.jwt.secret).toBe('a-very-long-secret-value');
  });

  it('decodes escaped newlines in the Firebase private key', () => {
    process.env.FIREBASE_PROJECT_ID = 'demo-project';
    process.env.FIREBASE_CLIENT_EMAIL =
      'sa@demo-project.iam.gserviceaccount.com';
    process.env.FIREBASE_PRIVATE_KEY =
      '-----BEGIN PRIVATE KEY-----\\nMOCKKEY\\n-----END PRIVATE KEY-----\\n';

    const config = configuration();

    expect(config.firebase.projectId).toBe('demo-project');
    expect(config.firebase.privateKey).toBe(
      '-----BEGIN PRIVATE KEY-----\nMOCKKEY\n-----END PRIVATE KEY-----\n',
    );
  });

  it('parses numeric env vars as numbers, not strings', () => {
    process.env.PORT = '4000';
    process.env.DATABASE_PORT = '5432';

    const config = configuration();

    expect(config.port).toBe(4000);
    expect(typeof config.port).toBe('number');
    expect(config.database.port).toBe(5432);
    expect(typeof config.database.port).toBe('number');
  });
});
