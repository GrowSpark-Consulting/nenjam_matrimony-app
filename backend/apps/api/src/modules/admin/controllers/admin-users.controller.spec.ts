import { Test, TestingModule } from '@nestjs/testing';
import { FirebaseAuthGuard } from '@app/common';
import { AdminGuard } from '../auth/admin.guard';
import { AdminUsersController } from './admin-users.controller';
import { AdminUsersService } from '../services/admin-users.service';
import type {
  AdminRequestContext,
  AuthenticatedAdmin,
} from '../auth/admin-request';
import type {
  AdminUserListQueryDto,
  BlockUserDto,
  CreateMemberNoteDto,
  RevealPiiDto,
  UnblockUserDto,
} from '../dto/admin-users.dto';

describe('AdminUsersController', () => {
  let controller: AdminUsersController;
  let service: jest.Mocked<AdminUsersService>;

  const mockAdmin: AuthenticatedAdmin = {
    adminAccountId: 'admin-acc-123',
    userId: 'admin-user-456',
    email: 'admin@nenjammatrimony.com',
    department: 'OPERATIONS',
    lastLoginAt: new Date(),
    sessionId: 'session-789',
    stepUpVerifiedAt: new Date(),
    roles: [{ key: 'SUPER_ADMIN', name: 'Super Admin' }],
    permissions: ['member.view', 'member.suspend', 'member.pii.reveal'],
  };

  const mockContext: AdminRequestContext = {
    requestId: 'req-abc-123',
    ipAddress: '127.0.0.1',
    userAgent: 'Jest/TestRunner',
  };

  beforeEach(async () => {
    const mockUsersService = {
      listUsers: jest.fn(),
      getStats: jest.fn(),
      getUserDetails: jest.fn(),
      blockUser: jest.fn(),
      unblockUser: jest.fn(),
      revealPii: jest.fn(),
      addNote: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      controllers: [AdminUsersController],
      providers: [
        {
          provide: AdminUsersService,
          useValue: mockUsersService,
        },
      ],
    })
      .overrideGuard(FirebaseAuthGuard)
      .useValue({ canActivate: () => true })
      .overrideGuard(AdminGuard)
      .useValue({ canActivate: () => true })
      .compile();

    controller = module.get<AdminUsersController>(AdminUsersController);
    service = module.get(AdminUsersService);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  describe('list', () => {
    it('delegates to usersService.listUsers with provided query', async () => {
      const query: AdminUserListQueryDto = { page: 2, limit: 10, search: 'test' };
      const expectedResult = {
        items: [],
        total: 0,
        page: 2,
        limit: 10,
        totalPages: 0,
      };
      service.listUsers.mockResolvedValue(expectedResult);

      const result = await controller.list(query);

      expect(service.listUsers).toHaveBeenCalledWith(query);
      expect(result).toBe(expectedResult);
    });
  });

  describe('stats', () => {
    it('delegates to usersService.getStats', async () => {
      const expectedStats = {
        totalUsers: 100,
        activeUsers: 80,
        blockedUsers: 5,
        registeredToday: 10,
        incompleteProfiles: 15,
        premiumMembers: 25,
      };
      service.getStats.mockResolvedValue(expectedStats);

      const result = await controller.stats();

      expect(service.getStats).toHaveBeenCalled();
      expect(result).toBe(expectedStats);
    });
  });

  describe('get', () => {
    it('delegates to usersService.getUserDetails with UUID', async () => {
      const userId = '11111111-1111-1111-1111-111111111111';
      const expectedDetails = { id: userId } as any;
      service.getUserDetails.mockResolvedValue(expectedDetails);

      const result = await controller.get(userId);

      expect(service.getUserDetails).toHaveBeenCalledWith(userId);
      expect(result).toBe(expectedDetails);
    });
  });

  describe('block', () => {
    it('delegates to usersService.blockUser with correct arguments', async () => {
      const userId = '22222222-2222-2222-2222-222222222222';
      const body: BlockUserDto = { reason: 'Violation of community guidelines' };
      const expectedResponse = {
        success: true,
        userId,
        previousStatus: 'ACTIVE' as const,
        status: 'BLOCKED' as const,
        reason: body.reason,
      };
      service.blockUser.mockResolvedValue(expectedResponse);

      const result = await controller.block(userId, body, mockAdmin, mockContext);

      expect(service.blockUser).toHaveBeenCalledWith(
        userId,
        mockAdmin,
        body.reason,
        mockContext,
      );
      expect(result).toBe(expectedResponse);
    });
  });

  describe('unblock', () => {
    it('delegates to usersService.unblockUser with correct arguments', async () => {
      const userId = '33333333-3333-3333-3333-333333333333';
      const body: UnblockUserDto = { reason: 'Verification proof submitted' };
      const expectedResponse = {
        success: true,
        userId,
        previousStatus: 'BLOCKED' as const,
        status: 'ACTIVE' as const,
      };
      service.unblockUser.mockResolvedValue(expectedResponse);

      const result = await controller.unblock(userId, body, mockAdmin, mockContext);

      expect(service.unblockUser).toHaveBeenCalledWith(
        userId,
        mockAdmin,
        mockContext,
        body.reason,
      );
      expect(result).toBe(expectedResponse);
    });
  });

  describe('revealPii', () => {
    it('delegates to usersService.revealPii with correct arguments', async () => {
      const userId = '44444444-4444-4444-4444-444444444444';
      const body: RevealPiiDto = { reason: 'Court order request' };
      const expectedResponse = {
        userId,
        email: 'member@test.local',
        phone: '+919876543210',
        location: null,
      };
      service.revealPii.mockResolvedValue(expectedResponse);

      const result = await controller.revealPii(
        userId,
        body,
        mockAdmin,
        mockContext,
      );

      expect(service.revealPii).toHaveBeenCalledWith(
        userId,
        mockAdmin,
        mockContext,
        body.reason,
      );
      expect(result).toBe(expectedResponse);
    });
  });

  describe('addNote', () => {
    it('delegates to usersService.addNote with correct arguments', async () => {
      const userId = '55555555-5555-5555-5555-555555555555';
      const body: CreateMemberNoteDto = { note: 'Candidate verified over phone.' };
      const expectedResponse = {
        id: 'note-1',
        userId,
        authorId: mockAdmin.userId,
        authorName: mockAdmin.email,
        note: body.note,
        createdAt: new Date(),
      };
      service.addNote.mockResolvedValue(expectedResponse);

      const result = await controller.addNote(userId, body, mockAdmin);

      expect(service.addNote).toHaveBeenCalledWith(userId, mockAdmin, body.note);
      expect(result).toBe(expectedResponse);
    });
  });
});
