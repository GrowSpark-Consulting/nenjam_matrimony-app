import { Controller, Get, Post, UseGuards } from '@nestjs/common';
import { AdminAuthController } from '../controllers/admin-auth.controller';
import { AdminMeController } from '../controllers/admin-me.controller';
import { AdminGuard } from './admin.guard';
import { findUnprotectedAdminRoutes } from './admin-route-check';
import {
  AdminController,
  AllowAnyAdmin,
  RequirePermissions,
} from './admin-route.decorators';

describe('findUnprotectedAdminRoutes', () => {
  @AdminController('admin/ok')
  class Declared {
    @Get()
    @RequirePermissions('plan.view')
    list() {}

    @Get('me')
    @AllowAnyAdmin()
    me() {}

    // Not a route: helpers on a controller are ignored.
    helper() {}
  }

  @AdminController('admin/leaky')
  class Leaky {
    @Get()
    @RequirePermissions('plan.view')
    list() {}

    @Post()
    forgotten() {}
  }

  @Controller('admin/method-level')
  class MethodLevel {
    @Get()
    @UseGuards(AdminGuard)
    guardedButUndeclared() {}
  }

  @Controller('members')
  class NotAdmin {
    @Get()
    open() {}
  }

  it('reports admin routes that declare no policy, and nothing else', () => {
    expect(
      findUnprotectedAdminRoutes([Declared, Leaky, MethodLevel, NotAdmin]),
    ).toEqual(['Leaky.forgotten', 'MethodLevel.guardedButUndeclared']);
  });

  it('passes the shipped admin controllers', () => {
    expect(
      findUnprotectedAdminRoutes([AdminAuthController, AdminMeController]),
    ).toEqual([]);
  });
});
