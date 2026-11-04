import { Body, Get, Param, Put } from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import { adminUnauthorized } from '../auth/admin-auth.policy';
import {
  AdminContext,
  type AdminRequestContext,
  type AuthenticatedAdmin,
  CurrentAdmin,
  hasFreshStepUp,
} from '../auth/admin-request';
import {
  AdminController,
  RequirePermissions,
} from '../auth/admin-route.decorators';
import { UpdatePlatformSettingDto } from '../dto/admin-settings.dto';

/**
 * Platform settings (commission and discount rules, limits). Reading needs
 * system.view; changing one needs config.edit, a reason, the version that was
 * read, and a fresh authenticator code — these values move money.
 */
@AdminController('admin/settings')
export class AdminSettingsController {
  constructor(private readonly settings: PlatformSettingsService) {}

  @Get()
  @RequirePermissions('system.view')
  @ApiOperation({ summary: 'Every platform setting, its value and version' })
  async list() {
    return { items: await this.settings.list() };
  }

  @Put(':key')
  @RequirePermissions('config.edit')
  @ApiOperation({
    summary:
      'Change one setting (reason, the version read, fresh authenticator code)',
  })
  update(
    @Param('key') key: string,
    @Body() body: UpdatePlatformSettingDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    if (!hasFreshStepUp(admin)) {
      throw adminUnauthorized(
        'ADMIN_STEP_UP_REQUIRED',
        'Changing a setting needs a fresh code from your authenticator app.',
      );
    }
    return this.settings.update({
      key,
      value: body.value,
      expectedVersion: body.version,
      reason: body.reason,
      actorId: admin.userId,
      context,
    });
  }
}
