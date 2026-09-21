import configuration from './configuration';

describe('configuration', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    process.env = { ...originalEnv };
    // Start hermetic. These four are read by configuration() but are NOT set
    // by most tests here, so whatever the surrounding environment happens to
    // export leaks into the result — `toEqual` on config.database/config.redis
    // then fails with an unexpected `url` key. It passed locally only because
    // jest loads no .env and a plain shell exports neither; CI sets both for
    // its service containers and caught it on the first run. Tests that want
    // these set them explicitly.
    delete process.env.DATABASE_URL;
    delete process.env.REDIS_URL;
    delete process.env.ELASTICSEARCH_USERNAME;
    delete process.env.ELASTICSEARCH_PASSWORD;
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

  it('surfaces REDIS_URL alongside the discrete fields, without altering them', () => {
    process.env.REDIS_URL =
      'rediss://default:secret@redis-cloud.example.com:6379';
    process.env.REDIS_HOST = 'redis.internal';
    process.env.REDIS_PORT = '6380';
    process.env.REDIS_USERNAME = 'default';
    process.env.REDIS_DB = '2';

    const config = configuration();

    expect(config.redis.url).toBe(
      'rediss://default:secret@redis-cloud.example.com:6379',
    );
    expect(config.redis.host).toBe('redis.internal');
    expect(config.redis.port).toBe(6380);
    expect(config.redis.username).toBe('default');
    expect(config.redis.db).toBe(2);
  });

  it('leaves REDIS_URL/username/db undefined when unset', () => {
    delete process.env.REDIS_URL;
    delete process.env.REDIS_USERNAME;
    delete process.env.REDIS_DB;

    const config = configuration();

    expect(config.redis.url).toBeUndefined();
    expect(config.redis.username).toBeUndefined();
    expect(config.redis.db).toBeUndefined();
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

describe('configuration: faceVerification', () => {
  const originalEnv = process.env;
  const FACE_VARS = [
    'FACE_VERIFICATION_ENABLED',
    'FACE_VERIFICATION_AWS_REGION',
    'FACE_VERIFICATION_AWS_ACCESS_KEY_ID',
    'FACE_VERIFICATION_AWS_SECRET_ACCESS_KEY',
    'FACE_LIVENESS_CLIENT_ROLE_ARN',
    'FACE_LIVENESS_CREDENTIALS_TTL_SECONDS',
    'FACE_LIVENESS_MIN_CONFIDENCE',
    'FACE_MATCH_MIN_SIMILARITY',
    'FACE_VERIFICATION_MAX_ATTEMPTS_PER_DAY',
    'FACE_VERIFICATION_GLOBAL_DAILY_CAP',
  ];

  beforeEach(() => {
    process.env = { ...originalEnv };
    for (const key of FACE_VARS) delete process.env[key];
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it('is off with the agreed defaults and no AWS identity when nothing is set', () => {
    expect(configuration().faceVerification).toEqual({
      enabled: false,
      region: 'ap-south-1',
      accessKeyId: undefined,
      secretAccessKey: undefined,
      clientRoleArn: undefined,
      credentialsTtlSeconds: 900,
      minLivenessConfidence: 90,
      minMatchSimilarity: 90,
      maxAttemptsPerDay: 3,
      globalDailyCap: 500,
    });
  });

  it('maps its own env vars and never reads the S3 credentials', () => {
    process.env.AWS_ACCESS_KEY_ID = 'AKIA-S3-KEY';
    process.env.AWS_SECRET_ACCESS_KEY = 's3-secret';
    process.env.FACE_VERIFICATION_ENABLED = 'true';
    process.env.FACE_VERIFICATION_AWS_REGION = 'us-east-1';
    process.env.FACE_VERIFICATION_AWS_ACCESS_KEY_ID = 'AKIA-FACE-KEY';
    process.env.FACE_VERIFICATION_AWS_SECRET_ACCESS_KEY = 'face-secret';
    process.env.FACE_LIVENESS_CLIENT_ROLE_ARN =
      'arn:aws:iam::123456789012:role/nenjam-face-liveness-client';
    process.env.FACE_LIVENESS_CREDENTIALS_TTL_SECONDS = '1200';
    process.env.FACE_LIVENESS_MIN_CONFIDENCE = '95.5';
    process.env.FACE_MATCH_MIN_SIMILARITY = '92';
    process.env.FACE_VERIFICATION_MAX_ATTEMPTS_PER_DAY = '5';
    process.env.FACE_VERIFICATION_GLOBAL_DAILY_CAP = '1000';

    expect(configuration().faceVerification).toEqual({
      enabled: true,
      region: 'us-east-1',
      accessKeyId: 'AKIA-FACE-KEY',
      secretAccessKey: 'face-secret',
      clientRoleArn:
        'arn:aws:iam::123456789012:role/nenjam-face-liveness-client',
      credentialsTtlSeconds: 1200,
      minLivenessConfidence: 95.5,
      minMatchSimilarity: 92,
      maxAttemptsPerDay: 5,
      globalDailyCap: 1000,
    });
  });

  it('only enables on an explicit "true" and treats blank numbers as unset', () => {
    process.env.FACE_VERIFICATION_ENABLED = 'yes';
    process.env.FACE_LIVENESS_MIN_CONFIDENCE = '';
    const face = configuration().faceVerification;
    expect(face.enabled).toBe(false);
    expect(face.minLivenessConfidence).toBe(90);
  });
});
