import {
  createParamDecorator,
  ExecutionContext,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';

// Attached by FirebaseAuthGuard after verifying the caller's Firebase ID
// token. `id` is the internal User row's id (what every repository query
// filters by); `uid` is the raw Firebase UID, kept for audit/logging.
export interface AuthenticatedUser {
  id: string;
  uid: string;
  email?: string;
  phone_number?: string;
}

interface RequestWithUser extends Request {
  user?: AuthenticatedUser;
}

// @CurrentUser() returns the full AuthenticatedUser; @CurrentUser('id') (or
// any other key) plucks a single field — e.g. `@CurrentUser('id') userId: string`.
export const CurrentUser = createParamDecorator(
  (data: keyof AuthenticatedUser | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest<RequestWithUser>();
    const user = request.user;

    if (!user) {
      // Only reachable if this decorator is used on a route not protected by
      // FirebaseAuthGuard — that's a wiring bug, not a client error.
      throw new UnauthorizedException('No authenticated user on the request.');
    }
    return data ? user[data] : user;
  },
);
