import {
  createParamDecorator,
  ExecutionContext,
  UnauthorizedException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { Request } from 'express';
import type { AuthenticatedUser } from '@app/common';
import type { PermissionKey } from '../rbac/permissions';

/** The staff member behind a request, attached by AdminGuard. */
export interface AuthenticatedAdmin {
  adminAccountId: string;
  userId: string;
  email: string;
  department: string;
  lastLoginAt: Date | null;
  /** Null only on the sign-in routes, before a session exists. */
  sessionId: string | null;
  roles: Array<{ key: string; name: string }>;
  permissions: PermissionKey[];
}

/** Where a request came from, recorded on every audit row it causes. */
export interface AdminRequestContext {
  requestId: string;
  ipAddress?: string;
  userAgent?: string;
}

export interface AdminRequest extends Request {
  user?: AuthenticatedUser;
  admin?: AuthenticatedAdmin;
  adminContext?: AdminRequestContext;
}

/**
 * The request's audit context, created once per request so every audit row it
 * writes shares one requestId. An incoming `x-request-id` (set by a proxy) is
 * kept when it looks sane; otherwise one is generated.
 */
export function requestContextOf(request: AdminRequest): AdminRequestContext {
  if (request.adminContext) return request.adminContext;
  const incoming = request.headers['x-request-id'];
  const requestId =
    typeof incoming === 'string' && /^[\w.-]{8,128}$/.test(incoming)
      ? incoming
      : randomUUID();
  const userAgent = request.headers['user-agent'];
  request.adminContext = {
    requestId,
    ipAddress: request.ip,
    userAgent:
      typeof userAgent === 'string' ? userAgent.slice(0, 512) : undefined,
  };
  return request.adminContext;
}

/** `@CurrentAdmin()` — only on routes behind AdminGuard. */
export const CurrentAdmin = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AuthenticatedAdmin => {
    const admin = ctx.switchToHttp().getRequest<AdminRequest>().admin;
    if (!admin) {
      // A wiring bug (route not behind AdminGuard), not a client error.
      throw new UnauthorizedException('No authenticated admin on the request.');
    }
    return admin;
  },
);

/** `@AdminContext()` — the request's audit context. */
export const AdminContext = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AdminRequestContext =>
    requestContextOf(ctx.switchToHttp().getRequest<AdminRequest>()),
);
