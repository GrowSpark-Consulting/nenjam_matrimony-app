import {
  Body,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import {
  type AdminRequestContext,
  type AuthenticatedAdmin,
  AdminContext,
  CurrentAdmin,
} from '../auth/admin-request';
import {
  AdminController,
  RequirePermissions,
} from '../auth/admin-route.decorators';
import {
  AdminUserListQueryDto,
  BlockUserDto,
  CreateMemberNoteDto,
  RevealPiiDto,
  UnblockUserDto,
} from '../dto/admin-users.dto';
import { AdminUsersService } from '../services/admin-users.service';

/**
 * Member user management API for Nenjam Matrimony staff.
 *
 * All routes are guarded by FirebaseAuthGuard and AdminGuard.
 * Sensitive PII reveal requires a fresh TOTP check within the last 10 minutes.
 * Status mutations (block/unblock) and PII reveals are transactionally / immutably audited.
 */
@AdminController('admin/users')
export class AdminUsersController {
  constructor(private readonly usersService: AdminUsersService) {}

  @Get()
  @RequirePermissions('member.view')
  @ApiOperation({ summary: 'Paginated & filtered member directory' })
  list(@Query() query: AdminUserListQueryDto) {
    return this.usersService.listUsers(query);
  }

  @Get('stats')
  @RequirePermissions('member.view')
  @ApiOperation({ summary: 'Real-time aggregate user statistics' })
  stats() {
    return this.usersService.getStats();
  }

  @Get(':id')
  @RequirePermissions('member.view')
  @ApiOperation({ summary: 'Complete member profile with 9-tab structure' })
  get(@Param('id', ParseUUIDPipe) id: string) {
    return this.usersService.getUserDetails(id);
  }

  @Patch(':id/block')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('member.suspend')
  @ApiOperation({
    summary:
      'Block user (sets BLOCKED status, writes audit log, invalidates Redis auth cache)',
  })
  block(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: BlockUserDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.usersService.blockUser(id, admin, body.reason, context);
  }

  @Patch(':id/unblock')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('member.suspend')
  @ApiOperation({
    summary:
      'Unblock user (restores ACTIVE status, writes audit log, invalidates Redis auth cache)',
  })
  unblock(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: UnblockUserDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.usersService.unblockUser(id, admin, context, body?.reason);
  }

  @Post(':id/reveal-pii')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('member.pii.reveal')
  @ApiOperation({
    summary:
      'Reveal sensitive PII (requires fresh TOTP step-up and writes audit log)',
  })
  revealPii(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: RevealPiiDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.usersService.revealPii(id, admin, context, body?.reason);
  }

  @Post(':id/notes')
  @HttpCode(HttpStatus.CREATED)
  @RequirePermissions('member.view')
  @ApiOperation({ summary: 'Add internal staff note on user profile' })
  addNote(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: CreateMemberNoteDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
  ) {
    return this.usersService.addNote(id, admin, body.note);
  }
}
