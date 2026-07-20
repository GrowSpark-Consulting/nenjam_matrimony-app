import * as Joi from 'joi';

export const validationSchema = Joi.object({
  NODE_ENV: Joi.string()
    .valid('development', 'production', 'test', 'staging')
    .default('development'),
  PORT: Joi.number().port().default(3000),
  WEBSOCKET_PORT: Joi.number().port().default(3001),

  DATABASE_HOST: Joi.string().required(),
  DATABASE_PORT: Joi.number().port().required(),
  DATABASE_USER: Joi.string().required(),
  DATABASE_PASSWORD: Joi.string().required(),
  DATABASE_NAME: Joi.string().required(),

  REDIS_HOST: Joi.string().required(),
  REDIS_PORT: Joi.number().port().required(),
  REDIS_PASSWORD: Joi.string().allow('').optional(),

  ELASTICSEARCH_NODE: Joi.string().uri().required(),

  SMTP_HOST: Joi.string().required(),
  SMTP_PORT: Joi.number().port().required(),
  SMTP_USER: Joi.string().allow('').optional(),
  SMTP_PASSWORD: Joi.string().allow('').optional(),

  JWT_SECRET: Joi.string().min(16).required(),

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

  LOG_LEVEL: Joi.string()
    .valid('error', 'warn', 'info', 'debug', 'verbose')
    .default('info'),
}).unknown(true);
