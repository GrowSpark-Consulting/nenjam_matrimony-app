# Redis Cloud Migration

## What changed
- Added Redis Cloud support using `REDIS_URL`.
- Preserved backward compatibility with `REDIS_HOST`/`PORT`/`USERNAME`/`PASSWORD`/`DB` configuration.
- Existing Redis consumers required no changes.
- Added configuration validation for `REDIS_URL`.
- Updated tests.
- Fixed the `RedisService` startup log to show the resolved host/port when `REDIS_URL` is used.
- Verified against a live Redis Cloud instance.

## Files modified
- `libs/config/src/configuration.ts`
- `libs/config/src/validation.ts`
- `libs/config/src/config.service.ts`
- `libs/cache/src/redis.module.ts`
- `libs/cache/src/redis.service.ts`
- `.env.example`
- `.env`
- `.env.local`
- `libs/config/src/configuration.spec.ts`
- `libs/config/src/validation.spec.ts`
- `libs/config/src/config.service.spec.ts`

## Verification
- Redis Cloud connection successful.
- All tests passed.
- Existing functionality preserved.

## Notes
- `REDIS_URL` is now the preferred configuration.
- Local Redis (Memurai) continues to work as a fallback.
