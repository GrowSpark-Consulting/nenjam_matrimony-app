import { ForbiddenException } from '@nestjs/common';
import { assertAdminPermission } from './assert-admin-permission';

describe('assertAdminPermission', () => {
  const staff = (over: Record<string, unknown> = {}) => ({
    role: 'ADMIN',
    status: 'ACTIVE',
    deletedAt: null,
    adminAccount: { isActive: true, roles: [{ roleId: 'r1' }] },
    ...over,
  });
  const db = (user: unknown) =>
    ({
      user: { findUnique: jest.fn().mockResolvedValue(user) },
    }) as never;

  async function refusal(user: unknown, actorId = 'u1') {
    try {
      await assertAdminPermission(db(user), actorId, 'plan.publish');
    } catch (error) {
      return error as ForbiddenException;
    }
    throw new Error('expected a refusal');
  }

  it('resolves for active staff whose role grants the key', async () => {
    await expect(
      assertAdminPermission(db(staff()), 'u1', 'plan.publish'),
    ).resolves.toBeUndefined();
  });

  it.each([
    ['no such user', null],
    ['a member', staff({ role: 'USER' })],
    ['a suspended admin', staff({ status: 'SUSPENDED' })],
    [
      'an inactive admin account',
      staff({ adminAccount: { isActive: false, roles: [{ roleId: 'r1' }] } }),
    ],
    [
      'no role granting it',
      staff({ adminAccount: { isActive: true, roles: [] } }),
    ],
  ])('refuses %s with the guard’s coded 403', async (_label, user) => {
    const error = await refusal(user);
    expect(error).toBeInstanceOf(ForbiddenException);
    expect(error.getResponse()).toEqual({
      statusCode: 403,
      error: 'Forbidden',
      code: 'ADMIN_PERMISSION_DENIED',
      message: 'Not permitted: requires plan.publish.',
      missing: ['plan.publish'],
    });
  });

  it('refuses an empty actor id without a database read', async () => {
    const database = db(staff());
    await expect(
      assertAdminPermission(database, '', 'plan.publish'),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });
});
