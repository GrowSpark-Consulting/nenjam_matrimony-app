import { Injectable, OnApplicationBootstrap, Type } from '@nestjs/common';
import { GUARDS_METADATA, METHOD_METADATA } from '@nestjs/common/constants';
import { DiscoveryService } from '@nestjs/core';
import { AdminGuard } from './admin.guard';
import { ADMIN_ROUTE_POLICY } from './admin-route-policy';

/**
 * `Controller.method` for every route behind AdminGuard that declares no
 * policy (`@RequirePermissions`, `@AllowAnyAdmin` or
 * `@AdminSessionNotRequired`).
 */
export function findUnprotectedAdminRoutes(
  controllers: ReadonlyArray<Type<unknown>>,
): string[] {
  const found: string[] = [];
  for (const controller of controllers) {
    const classGuards = guardsOf(controller);
    const proto = controller.prototype as Record<string, unknown>;
    for (const name of Object.getOwnPropertyNames(proto)) {
      if (name === 'constructor') continue;
      const handler = proto[name];
      if (typeof handler !== 'function') continue;
      if (Reflect.getMetadata(METHOD_METADATA, handler) === undefined) continue;
      const guarded =
        classGuards.includes(AdminGuard) ||
        guardsOf(handler).includes(AdminGuard);
      if (guarded && !Reflect.getMetadata(ADMIN_ROUTE_POLICY, handler)) {
        found.push(`${controller.name}.${name}`);
      }
    }
  }
  return found;
}

function guardsOf(target: object): unknown[] {
  return (Reflect.getMetadata(GUARDS_METADATA, target) as unknown[]) ?? [];
}

/**
 * Refuses to start the API with an admin route that declares no policy. The
 * guard already denies such a route at request time; this makes the mistake
 * visible in CI's boot smoke test instead of as a mysterious 403 in
 * production.
 */
@Injectable()
export class AdminRouteCheck implements OnApplicationBootstrap {
  constructor(private readonly discovery: DiscoveryService) {}

  onApplicationBootstrap(): void {
    const controllers = this.discovery
      .getControllers()
      .map((wrapper) => wrapper.metatype)
      .filter((metatype): metatype is Type<unknown> => !!metatype);
    const unprotected = findUnprotectedAdminRoutes(controllers);
    if (unprotected.length > 0) {
      throw new Error(
        `Admin routes without @RequirePermissions/@AllowAnyAdmin: ${unprotected.join(', ')}`,
      );
    }
  }
}
