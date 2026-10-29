import { Get } from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import { type AuthenticatedAdmin, CurrentAdmin } from '../auth/admin-request';
import { AdminController, AllowAnyAdmin } from '../auth/admin-route.decorators';
import { AdminMeResponseDto } from '../dto/admin-auth.dto';

@AdminController('admin')
export class AdminMeController {
  /**
   * The signed-in admin and the permission keys they hold. The admin panel
   * builds its navigation and buttons from `permissions`; every route checks
   * them again server-side regardless.
   */
  @Get('me')
  @AllowAnyAdmin()
  @ApiOperation({ summary: 'Current admin, roles and permission keys' })
  me(@CurrentAdmin() admin: AuthenticatedAdmin): AdminMeResponseDto {
    return {
      adminAccountId: admin.adminAccountId,
      userId: admin.userId,
      email: admin.email,
      department: admin.department,
      lastLoginAt: admin.lastLoginAt,
      roles: admin.roles,
      permissions: admin.permissions,
    };
  }
}
