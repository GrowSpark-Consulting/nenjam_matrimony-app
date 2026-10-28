import type * as Joi from 'joi';
import { validationSchema } from './validation';

describe('validationSchema', () => {
  const validEnv = {
    NODE_ENV: 'development',
    PORT: '3000',
    WEBSOCKET_PORT: '3001',
    DATABASE_HOST: 'localhost',
    DATABASE_PORT: '5432',
    DATABASE_USER: 'postgres',
    DATABASE_PASSWORD: 'postgres',
    DATABASE_NAME: 'app',
    REDIS_HOST: 'localhost',
    REDIS_PORT: '6379',
    ELASTICSEARCH_NODE: 'http://localhost:9200',
    SMTP_HOST: 'localhost',
    SMTP_PORT: '1025',
    JWT_SECRET: 'a-very-long-secret-value',
    LOG_LEVEL: 'debug',
  };

  it('passes when all required variables are present and valid', () => {
    const { error } = validationSchema.validate(validEnv, {
      abortEarly: false,
    });
    expect(error).toBeUndefined();
  });

  it('allows unrelated OS-level env vars to pass through', () => {
    const { error } = validationSchema.validate(
      { ...validEnv, PATH: '/usr/bin', HOME: '/home/user' },
      { abortEarly: false },
    );
    expect(error).toBeUndefined();
  });

  // DATABASE_* and REDIS_HOST/REDIS_PORT are intentionally optional: a
  // deployment may point at a shared managed instance with a single
  // DATABASE_URL / REDIS_URL instead of the discrete fields (see
  // validation.ts). They are covered separately below.
  it.each(['ELASTICSEARCH_NODE', 'SMTP_HOST', 'SMTP_PORT', 'JWT_SECRET'])(
    'fails when required variable %s is missing',
    (key) => {
      const env = { ...validEnv };
      delete (env as Record<string, string>)[key];

      const { error } = validationSchema.validate(env, { abortEarly: false });
      expect(error).toBeDefined();
      expect(error?.message).toContain(key);
    },
  );

  it('passes with a single DATABASE_URL and no discrete DATABASE_* fields', () => {
    const env = { ...validEnv } as Record<string, string>;
    for (const k of [
      'DATABASE_HOST',
      'DATABASE_PORT',
      'DATABASE_USER',
      'DATABASE_PASSWORD',
      'DATABASE_NAME',
    ]) {
      delete env[k];
    }
    env.DATABASE_URL = 'postgresql://u:p@host/db?sslmode=require';

    const { error } = validationSchema.validate(env, { abortEarly: false });
    expect(error).toBeUndefined();
  });

  it('passes with a single REDIS_URL and no discrete REDIS_* fields', () => {
    const env = { ...validEnv } as Record<string, string>;
    delete env.REDIS_HOST;
    delete env.REDIS_PORT;
    env.REDIS_URL = 'rediss://default:secret@redis-cloud.example.com:6379';

    const { error } = validationSchema.validate(env, { abortEarly: false });
    expect(error).toBeUndefined();
  });

  it('accepts REDIS_USERNAME and REDIS_DB alongside the discrete fields', () => {
    const { error } = validationSchema.validate(
      { ...validEnv, REDIS_USERNAME: 'default', REDIS_DB: '2' },
      { abortEarly: false },
    );
    expect(error).toBeUndefined();
  });

  it('fails when JWT_SECRET is shorter than 16 characters', () => {
    const { error } = validationSchema.validate(
      { ...validEnv, JWT_SECRET: 'short' },
      { abortEarly: false },
    );
    expect(error).toBeDefined();
  });

  it('fails when ELASTICSEARCH_NODE is not a valid URI', () => {
    const { error } = validationSchema.validate(
      { ...validEnv, ELASTICSEARCH_NODE: 'not-a-url' },
      { abortEarly: false },
    );
    expect(error).toBeDefined();
  });

  it('defaults NODE_ENV and LOG_LEVEL when omitted', () => {
    const env = { ...validEnv };
    delete (env as Record<string, string>).NODE_ENV;
    delete (env as Record<string, string>).LOG_LEVEL;

    const { error, value } = validationSchema.validate(env, {
      abortEarly: false,
    }) as { error?: Joi.ValidationError; value: Record<string, string> };
    expect(error).toBeUndefined();
    expect(value.NODE_ENV).toBe('development');
    expect(value.LOG_LEVEL).toBe('info');
  });

  describe('ADMIN_MFA_ENCRYPTION_KEY', () => {
    const withKey = (key?: string) =>
      validationSchema.validate(
        key === undefined
          ? validEnv
          : { ...validEnv, ADMIN_MFA_ENCRYPTION_KEY: key },
        { abortEarly: false },
      ).error;

    it('is optional: absent or blank boots (admin sign-in then answers 503)', () => {
      expect(withKey()).toBeUndefined();
      expect(withKey('')).toBeUndefined();
    });

    it('accepts 32 bytes, base64-encoded', () => {
      expect(withKey(Buffer.alloc(32, 7).toString('base64'))).toBeUndefined();
    });

    it('refuses to boot with a malformed key rather than run without MFA', () => {
      expect(withKey('not-a-key')).toBeDefined();
      expect(withKey(Buffer.alloc(16, 7).toString('base64'))).toBeDefined();
    });
  });
});

describe('validationSchema: face verification', () => {
  const base = {
    ELASTICSEARCH_NODE: 'http://localhost:9200',
    SMTP_HOST: 'localhost',
    SMTP_PORT: '1025',
    JWT_SECRET: 'a-very-long-secret-value',
  };

  function validate(extra: Record<string, string>) {
    return validationSchema.validate(
      { ...base, ...extra },
      { abortEarly: false },
    ) as {
      error?: Joi.ValidationError;
      value: Record<string, unknown>;
    };
  }

  it('boots with every face-verification value absent, off by default', () => {
    const { error, value } = validate({});
    expect(error).toBeUndefined();
    expect(value.FACE_VERIFICATION_ENABLED).toBe(false);
    expect(value.FACE_LIVENESS_CREDENTIALS_TTL_SECONDS).toBe(900);
    expect(value.FACE_LIVENESS_MIN_CONFIDENCE).toBe(90);
    expect(value.FACE_MATCH_MIN_SIMILARITY).toBe(90);
    expect(value.FACE_VERIFICATION_MAX_ATTEMPTS_PER_DAY).toBe(3);
    expect(value.FACE_VERIFICATION_GLOBAL_DAILY_CAP).toBe(500);
  });

  it('accepts blank credentials/role (the .env.example shape)', () => {
    const { error } = validate({
      FACE_VERIFICATION_AWS_REGION: 'ap-south-1',
      FACE_VERIFICATION_AWS_ACCESS_KEY_ID: '',
      FACE_VERIFICATION_AWS_SECRET_ACCESS_KEY: '',
      FACE_LIVENESS_CLIENT_ROLE_ARN: '',
    });
    expect(error).toBeUndefined();
  });

  it('accepts a real-shaped role ARN and rejects anything else', () => {
    expect(
      validate({
        FACE_LIVENESS_CLIENT_ROLE_ARN:
          'arn:aws:iam::123456789012:role/nenjam-face-liveness-client',
      }).error,
    ).toBeUndefined();
    expect(
      validate({ FACE_LIVENESS_CLIENT_ROLE_ARN: 'nenjam-face-liveness-client' })
        .error,
    ).toBeDefined();
    expect(
      validate({
        FACE_LIVENESS_CLIENT_ROLE_ARN: 'arn:aws:iam::123456789012:user/someone',
      }).error,
    ).toBeDefined();
  });

  it.each([
    ['FACE_LIVENESS_CREDENTIALS_TTL_SECONDS', '899'],
    ['FACE_LIVENESS_CREDENTIALS_TTL_SECONDS', '3601'],
    ['FACE_LIVENESS_MIN_CONFIDENCE', '101'],
    ['FACE_MATCH_MIN_SIMILARITY', '-1'],
    ['FACE_VERIFICATION_MAX_ATTEMPTS_PER_DAY', '0'],
    ['FACE_VERIFICATION_GLOBAL_DAILY_CAP', '0'],
    ['FACE_VERIFICATION_AWS_REGION', 'mumbai'],
    ['FACE_VERIFICATION_ENABLED', 'maybe'],
  ])('rejects %s=%s', (key, raw) => {
    expect(validate({ [key]: raw }).error).toBeDefined();
  });
});
