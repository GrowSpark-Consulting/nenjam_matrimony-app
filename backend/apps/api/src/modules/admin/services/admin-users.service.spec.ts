import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { UserStatus } from '../../../../../../libs/database/generated/client';
import type { AuthenticatedAdmin, AdminRequestContext } from '../auth/admin-request';
import { AdminUsersService } from './admin-users.service';

describe('AdminUsersService', () => {
  let service: AdminUsersService;
  let prisma: any;
  let redis: any;
  let auditService: any;

  const mockAdmin: AuthenticatedAdmin = {
    adminAccountId: 'admin-acc-1',
    userId: 'admin-user-1',
    email: 'admin@nenjam.com',
    department: 'PLATFORM',
    lastLoginAt: new Date(),
    sessionId: 'session-1',
    stepUpVerifiedAt: new Date(),
    roles: [{ key: 'SUPER_ADMIN', name: 'Super Admin' }],
    permissions: ['member.view', 'member.suspend', 'member.pii.reveal'],
  };

  const mockContext: AdminRequestContext = {
    requestId: 'req-123',
    ipAddress: '127.0.0.1',
    userAgent: 'Jest-Test',
  };

  beforeEach(() => {
    prisma = {
      user: {
        findMany: jest.fn(),
        findUnique: jest.fn(),
        count: jest.fn(),
        update: jest.fn(),
      },
      userSubscription: {
        count: jest.fn(),
      },
      memberNote: {
        create: jest.fn(),
      },
      $transaction: jest.fn(async (cb) => cb(prisma)),
    };

    redis = {
      getClient: jest.fn().mockReturnValue({
        status: 'ready',
        del: jest.fn().mockResolvedValue(1),
      }),
    };

    auditService = {
      record: jest.fn().mockResolvedValue(undefined),
      recordBestEffort: jest.fn().mockResolvedValue(undefined),
    };

    service = new AdminUsersService(prisma, redis, auditService);
  });

  describe('listUsers', () => {
    it('returns paginated and formatted users with masked contact info', async () => {
      prisma.user.count.mockResolvedValue(1);
      prisma.user.findMany.mockResolvedValue([
        {
          id: 'user-uuid-1',
          email: 'member@test.com',
          phone: '+919876543210',
          role: 'USER',
          status: 'ACTIVE',
          createdAt: new Date('2026-01-01T00:00:00Z'),
          updatedAt: new Date('2026-01-01T00:00:00Z'),
          profile: {
            firstName: 'Karthik',
            lastName: 'Raman',
            dob: new Date('1995-05-15T00:00:00Z'),
            gender: 'MALE',
            currentCity: 'Chennai',
            currentState: 'Tamil Nadu',
            country: 'India',
            isProfileComplete: true,
            profileCompletePct: 100,
          },
          photos: [{ cdnUrl: 'https://cdn.nenjam.com/p1.jpg', isApproved: true }],
          subscriptions: [
            {
              id: 'sub-1',
              status: 'ACTIVE',
              startDate: new Date('2026-01-01'),
              endDate: new Date('2026-12-31'),
              plan: { name: 'GOLD', displayName: 'Gold Tier', tier: 2 },
            },
          ],
        },
      ]);

      const result = await service.listUsers({ page: 1, limit: 10 });

      expect(result.total).toBe(1);
      expect(result.page).toBe(1);
      expect(result.totalPages).toBe(1);
      expect(result.items).toHaveLength(1);

      const user = result.items[0];
      expect(user.id).toBe('user-uuid-1');
      expect(user.fullName).toBe('Karthik Raman');
      expect(user.phone).toContain('***'); // masked
      expect(user.email).toContain('***'); // masked
      expect(user.membership).toBe('Gold Tier');
      expect(user.membershipCode).toBe('GOLD');
      expect(user.profileStatus).toBe('COMPLETE');
      expect(user.accountStatus).toBe('ACTIVE');
      expect(user.age).toBeGreaterThan(25);
    });

    it('filters by status and profile completion status', async () => {
      prisma.user.count.mockResolvedValue(0);
      prisma.user.findMany.mockResolvedValue([]);

      await service.listUsers({
        status: 'BLOCKED',
        profileComplete: false,
        gender: 'FEMALE',
      });

      expect(prisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            deletedAt: null,
            status: 'BLOCKED',
            profile: expect.objectContaining({
              gender: 'FEMALE',
              isProfileComplete: false,
            }),
          }),
        }),
      );
    });

    it('handles search queries by name, email, or phone', async () => {
      prisma.user.count.mockResolvedValue(0);
      prisma.user.findMany.mockResolvedValue([]);

      await service.listUsers({ search: 'Priya' });

      expect(prisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            OR: expect.arrayContaining([
              { email: { contains: 'Priya', mode: 'insensitive' } },
              { phone: { contains: 'Priya' } },
            ]),
          }),
        }),
      );
    });
  });

  describe('getStats', () => {
    it('aggregates user counts correctly', async () => {
      prisma.user.count
        .mockResolvedValueOnce(500) // total
        .mockResolvedValueOnce(450) // active
        .mockResolvedValueOnce(20)  // blocked
        .mockResolvedValueOnce(15)  // registered today
        .mockResolvedValueOnce(80); // incomplete profiles
      prisma.userSubscription.count.mockResolvedValueOnce(120); // premium

      const stats = await service.getStats();

      expect(stats.totalUsers).toBe(500);
      expect(stats.activeUsers).toBe(450);
      expect(stats.blockedUsers).toBe(20);
      expect(stats.registeredToday).toBe(15);
      expect(stats.incompleteProfiles).toBe(80);
      expect(stats.premiumMembers).toBe(120);
    });
  });

  describe('getUserDetails', () => {
    it('returns full tabs data with masked contact details', async () => {
      prisma.user.findUnique.mockResolvedValue({
        id: 'user-1',
        firebaseUid: 'fb-123',
        status: 'ACTIVE',
        role: 'USER',
        trustScore: 85,
        email: 'john.doe@example.com',
        phone: '+919123456789',
        createdAt: new Date('2026-02-01'),
        updatedAt: new Date('2026-02-01'),
        deletedAt: null,
        profile: {
          firstName: 'John',
          lastName: 'Doe',
          dob: new Date('1992-04-10'),
          gender: 'MALE',
          maritalStatus: 'NEVER_MARRIED',
          religion: 'Hindu',
          caste: 'Brahmin',
          highestEducation: 'B.Tech',
          profession: 'Software Engineer',
          annualIncomeLakhs: '25.00',
          currentCity: 'Bangalore',
          currentState: 'Karnataka',
          country: 'India',
          isProfileComplete: true,
          profileCompletePct: 90,
        },
        photos: [
          { id: 'photo-1', cdnUrl: 'https://cdn.nenjam.com/1.jpg', isPrimary: true, order: 0, isApproved: true },
        ],
        subscriptions: [],
        partnerPreference: { minAge: 25, maxAge: 30 },
        astrologyProfile: { rashi: 'Mesha' },
        faceVerification: { status: 'VERIFIED' },
        kycVerifications: [],
        memberNotes: [],
        supportTickets: [],
        trustScoreLogs: [],
        _count: { blocksMade: 1, blocksReceived: 0, reportsMade: 0, reportsAgainst: 0 },
      });

      const details = await service.getUserDetails('user-1');

      expect(details.id).toBe('user-1');
      expect(details.basicInfo.fullName).toBe('John Doe');
      expect(details.basicInfo.maritalStatus).toBe('NEVER_MARRIED');
      expect(details.contactInfo.phone).toContain('***');
      expect(details.contactInfo.email).toContain('***');
      expect(details.photosAndMedia.verification.faceVerified).toBe(true);
      expect(details.accountActivity.trustScore).toBe(85);
    });

    it('throws NotFoundException if user is deleted or does not exist', async () => {
      prisma.user.findUnique.mockResolvedValue(null);

      await expect(service.getUserDetails('non-existent')).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('blockUser', () => {
    it('successfully blocks an active user and writes audit log', async () => {
      prisma.user.findUnique.mockResolvedValue({
        id: 'target-user',
        status: UserStatus.ACTIVE,
        firebaseUid: 'fb-target',
        deletedAt: null,
      });

      const result = await service.blockUser(
        'target-user',
        mockAdmin,
        'Violated terms of service with inappropriate behavior',
        mockContext,
      );

      expect(result.success).toBe(true);
      expect(result.status).toBe(UserStatus.BLOCKED);
      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: 'target-user' },
        data: { status: UserStatus.BLOCKED },
      });
      expect(auditService.record).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          action: 'member.block',
          entity: 'User',
          entityId: 'target-user',
          reason: 'Violated terms of service with inappropriate behavior',
          before: { status: UserStatus.ACTIVE },
          after: { status: UserStatus.BLOCKED },
        }),
      );
    });

    it('rejects blocking if user is already blocked', async () => {
      prisma.user.findUnique.mockResolvedValue({
        id: 'target-user',
        status: UserStatus.BLOCKED,
        firebaseUid: 'fb-target',
        deletedAt: null,
      });

      await expect(
        service.blockUser('target-user', mockAdmin, 'Already blocked', mockContext),
      ).rejects.toThrow(ConflictException);
    });

    it('rejects blocking if reason is missing or too short', async () => {
      await expect(
        service.blockUser('target-user', mockAdmin, 'ab', mockContext),
      ).rejects.toThrow(BadRequestException);
    });

    it('throws NotFoundException if user not found', async () => {
      prisma.user.findUnique.mockResolvedValue(null);

      await expect(
        service.blockUser('target-user', mockAdmin, 'Valid reason', mockContext),
      ).rejects.toThrow(NotFoundException);
    });
  });

  describe('unblockUser', () => {
    it('successfully unblocks a blocked user and restores ACTIVE status', async () => {
      prisma.user.findUnique.mockResolvedValue({
        id: 'blocked-user',
        status: UserStatus.BLOCKED,
        firebaseUid: 'fb-blocked',
        deletedAt: null,
      });

      const result = await service.unblockUser(
        'blocked-user',
        mockAdmin,
        mockContext,
        'User verified identity and appealed',
      );

      expect(result.success).toBe(true);
      expect(result.status).toBe(UserStatus.ACTIVE);
      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: 'blocked-user' },
        data: { status: UserStatus.ACTIVE },
      });
      expect(auditService.record).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          action: 'member.unblock',
          entity: 'User',
          entityId: 'blocked-user',
          before: { status: UserStatus.BLOCKED },
          after: { status: UserStatus.ACTIVE },
        }),
      );
    });

    it('throws BadRequestException if user is not blocked', async () => {
      prisma.user.findUnique.mockResolvedValue({
        id: 'active-user',
        status: UserStatus.ACTIVE,
        firebaseUid: 'fb-active',
        deletedAt: null,
      });

      await expect(
        service.unblockUser('active-user', mockAdmin, mockContext),
      ).rejects.toThrow(BadRequestException);
    });
  });

  describe('revealPii', () => {
    it('returns unmasked phone and email while recording member.pii.reveal audit', async () => {
      prisma.user.findUnique.mockResolvedValue({
        id: 'user-1',
        email: 'secret@example.com',
        phone: '+919999888877',
        deletedAt: null,
        profile: {
          currentCity: 'Madurai',
          currentState: 'Tamil Nadu',
          country: 'India',
          pinCode: '625001',
        },
      });

      const result = await service.revealPii(
        'user-1',
        mockAdmin,
        mockContext,
        'Investigating identity fraud complaint',
      );

      expect(result.email).toBe('secret@example.com');
      expect(result.phone).toBe('+919999888877');
      expect(auditService.recordBestEffort).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'member.pii.reveal',
          entity: 'User',
          entityId: 'user-1',
          reason: 'Investigating identity fraud complaint',
        }),
      );
    });
  });

  describe('addNote', () => {
    it('adds internal note by an admin', async () => {
      prisma.user.findUnique.mockResolvedValue({ id: 'user-1', deletedAt: null });
      prisma.memberNote.create.mockResolvedValue({
        id: 'note-1',
        userId: 'user-1',
        authorId: mockAdmin.userId,
        authorName: mockAdmin.email,
        note: 'Customer called support regarding photo upload assistance.',
        createdAt: new Date(),
      });

      const note = await service.addNote(
        'user-1',
        mockAdmin,
        'Customer called support regarding photo upload assistance.',
      );

      expect(note.id).toBe('note-1');
      expect(note.note).toBe('Customer called support regarding photo upload assistance.');
      expect(prisma.memberNote.create).toHaveBeenCalled();
    });

    it('rejects empty note', async () => {
      await expect(service.addNote('user-1', mockAdmin, '  ')).rejects.toThrow(
        BadRequestException,
      );
    });
  });
});

