import {
  ForbiddenException,
  HttpException,
  HttpStatus,
  UnauthorizedException,
} from '@nestjs/common';

/**
 * Session and second-factor policy for staff (Admin Architecture v3,
 * section 13). Security constants rather than settings: loosening any of them
 * should take a code review, not an admin-panel click.
 */

/** Header carrying the admin session token, alongside the Firebase ID token. */
export const ADMIN_SESSION_HEADER = 'x-admin-session';

/** A session ends this long after the authenticator check, however busy. */
export const ADMIN_SESSION_MAX_AGE_MS = 12 * 60 * 60 * 1000;
/** ...or after this long without a request. */
export const ADMIN_SESSION_IDLE_MS = 30 * 60 * 1000;
/** lastSeenAt is written at most this often (idle is measured with that slack). */
export const ADMIN_SESSION_TOUCH_INTERVAL_MS = 60 * 1000;
/** Sensitive permissions need an authenticator check at most this old. */
export const ADMIN_STEP_UP_MS = 10 * 60 * 1000;

/** Wrong codes in a row before the account's second factor is locked... */
export const ADMIN_MFA_MAX_FAILURES = 5;
/** ...for this long. */
export const ADMIN_MFA_LOCK_MS = 15 * 60 * 1000;
/** How long a provisioning script's enrolment code stays valid. */
export const ADMIN_ENROLLMENT_CODE_TTL_MS = 24 * 60 * 60 * 1000;

export type AdminErrorCode =
  | 'ADMIN_ACCESS_REQUIRED'
  | 'ADMIN_PERMISSION_DENIED'
  | 'ADMIN_ROUTE_UNPROTECTED'
  | 'ADMIN_SESSION_REQUIRED'
  | 'ADMIN_SESSION_INVALID'
  | 'ADMIN_STEP_UP_REQUIRED'
  | 'ADMIN_MFA_NOT_ENROLLED'
  | 'ADMIN_MFA_ALREADY_ENROLLED'
  | 'ADMIN_MFA_INVALID_CODE'
  | 'ADMIN_MFA_LOCKED'
  | 'ADMIN_ENROLLMENT_CODE_INVALID';

/**
 * Nest's usual error shape plus a stable `code` — the same convention as the
 * membership denials — so the admin panel can branch without parsing text.
 * 401 means "authenticate (again)", 403 means "authenticated, not allowed".
 */
function body(
  statusCode: number,
  error: string,
  code: AdminErrorCode,
  message: string,
  extra?: Record<string, unknown>,
) {
  return { statusCode, error, code, message, ...extra };
}

export function adminForbidden(
  code: AdminErrorCode,
  message: string,
  extra?: Record<string, unknown>,
): ForbiddenException {
  return new ForbiddenException(body(403, 'Forbidden', code, message, extra));
}

export function adminUnauthorized(
  code: AdminErrorCode,
  message: string,
): UnauthorizedException {
  return new UnauthorizedException(body(401, 'Unauthorized', code, message));
}

export function adminLocked(retryAfterSeconds: number): HttpException {
  return new HttpException(
    body(
      429,
      'Too Many Requests',
      'ADMIN_MFA_LOCKED',
      'Too many incorrect codes. Try again later.',
      { retryAfterSeconds },
    ),
    HttpStatus.TOO_MANY_REQUESTS,
  );
}
