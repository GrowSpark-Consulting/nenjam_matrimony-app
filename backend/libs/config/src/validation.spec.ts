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

  it.each([
    'DATABASE_HOST',
    'DATABASE_PORT',
    'DATABASE_USER',
    'DATABASE_PASSWORD',
    'DATABASE_NAME',
    'REDIS_HOST',
    'REDIS_PORT',
    'ELASTICSEARCH_NODE',
    'SMTP_HOST',
    'SMTP_PORT',
    'JWT_SECRET',
  ])('fails when required variable %s is missing', (key) => {
    const env = { ...validEnv };
    delete (env as Record<string, string>)[key];

    const { error } = validationSchema.validate(env, { abortEarly: false });
    expect(error).toBeDefined();
    expect(error?.message).toContain(key);
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
});
