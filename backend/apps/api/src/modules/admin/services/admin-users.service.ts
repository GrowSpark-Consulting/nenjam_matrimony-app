import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '@app/database';
import { RedisService } from '@app/cache';
import { invalidateCachedUserId } from '@app/common';
import { maskEmailForDisplay } from '@app/mail';
import { maskPhone } from '../../agents/referral/agent-referral-view';
import { ageOnIstDate } from '../../agents/adapters/prisma/prisma-agent-member-read';
import {
  Prisma,
  SubscriptionPlanName,
  UserStatus,
} from '../../../../../../libs/database/generated/client';
import type {
  AdminRequestContext,
  AuthenticatedAdmin,
} from '../auth/admin-request';
import type {
  AdminUserListQueryDto,
} from '../dto/admin-users.dto';
import { AdminAuditService } from './admin-audit.service';

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

@Injectable()
export class AdminUsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly auditService: AdminAuditService,
  ) {}

  /**
   * Server-side paginated & filtered list of registered users.
   */
  async listUsers(query: AdminUserListQueryDto) {
    const page = Math.max(1, query.page ?? 1);
    const limit = Math.min(100, Math.max(1, query.limit ?? 20));
    const skip = (page - 1) * limit;
    const now = new Date();

    const where: Prisma.UserWhereInput = {
      deletedAt: null,
    };

    // Text search by ID, email, phone, or name
    if (query.search?.trim()) {
      const q = query.search.trim();
      if (UUID_REGEX.test(q)) {
        where.id = q;
      } else if (q.includes('@')) {
        where.email = { contains: q, mode: 'insensitive' };
      } else if (/^\+?\d[\d\s-]{4,}$/.test(q)) {
        const digits = q.replace(/[\s-]/g, '');
        where.phone = { contains: digits };
      } else {
        where.OR = [
          { email: { contains: q, mode: 'insensitive' } },
          { phone: { contains: q } },
          {
            profile: {
              OR: [
                { firstName: { contains: q, mode: 'insensitive' } },
                { lastName: { contains: q, mode: 'insensitive' } },
              ],
            },
          },
        ];
      }
    }

    const profileFilter: Prisma.UserProfileWhereInput = {};
    if (query.gender) {
      profileFilter.gender = query.gender;
    }
    if (query.profileComplete !== undefined) {
      profileFilter.isProfileComplete = query.profileComplete;
    }
    if (Object.keys(profileFilter).length > 0) {
      where.profile = profileFilter;
    }

    if (query.status) {
      where.status = query.status as UserStatus;
    }

    if (query.registeredFrom || query.registeredTo) {
      where.createdAt = {
        ...(query.registeredFrom && { gte: new Date(query.registeredFrom) }),
        ...(query.registeredTo && { lte: new Date(query.registeredTo) }),
      };
    }

    if (query.membership?.trim()) {
      const planName = query.membership.trim().toUpperCase() as SubscriptionPlanName;
      where.subscriptions = {
        some: {
          status: 'ACTIVE',
          endDate: { gt: now },
          plan: { name: planName },
        },
      };
    }

    const orderBy: Prisma.UserOrderByWithRelationInput =
      query.sortBy === 'name'
        ? { profile: { firstName: query.sortOrder ?? 'desc' } }
        : query.sortBy === 'status'
          ? { status: query.sortOrder ?? 'desc' }
          : { createdAt: query.sortOrder ?? 'desc' };

    const [total, users] = await Promise.all([
      this.prisma.user.count({ where }),
      this.prisma.user.findMany({
        where,
        skip,
        take: limit,
        orderBy,
        include: {
          profile: true,
          photos: {
            where: { isPrimary: true },
            take: 1,
          },
          subscriptions: {
            where: { status: 'ACTIVE', endDate: { gt: now } },
            orderBy: { endDate: 'desc' },
            take: 1,
            include: { plan: true },
          },
        },
      }),
    ]);

    const items = users.map((u) => {
      const profile = u.profile;
      const primaryPhoto = u.photos[0] ?? null;
      const activeSub = u.subscriptions[0] ?? null;

      const age = profile?.dob ? ageOnIstDate(profile.dob, now) : null;
      const fullName = profile
        ? `${profile.firstName} ${profile.lastName}`.trim()
        : null;
      const location = profile
        ? [profile.currentCity, profile.currentState].filter(Boolean).join(', ')
        : null;

      return {
        id: u.id,
        fullName: fullName || 'Incomplete Profile',
        gender: profile?.gender ?? null,
        age,
        location: location || null,
        phone: u.phone ? maskPhone(u.phone) : null,
        email: u.email.endsWith('@firebase.invalid')
          ? null
          : maskEmailForDisplay(u.email),
        membership: activeSub?.plan?.displayName || activeSub?.plan?.name || 'Free',
        membershipCode: activeSub?.plan?.name || 'FREE',
        profileStatus: profile?.isProfileComplete ? 'COMPLETE' : 'INCOMPLETE',
        profileCompletePct: profile?.profileCompletePct ?? 0,
        accountStatus: u.status,
        primaryPhotoUrl: primaryPhoto?.cdnUrl ?? null,
        photoApproved: primaryPhoto?.isApproved ?? false,
        registrationDate: u.createdAt,
      };
    });

    return {
      items,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  /**
   * Aggregate statistics for the User Management Dashboard.
   */
  async getStats() {
    const now = new Date();
    const todayStart = new Date(now);
    todayStart.setUTCHours(0, 0, 0, 0);

    const [
      totalUsers,
      activeUsers,
      blockedUsers,
      registeredToday,
      incompleteProfiles,
      premiumMembers,
    ] = await Promise.all([
      this.prisma.user.count({ where: { deletedAt: null } }),
      this.prisma.user.count({
        where: { deletedAt: null, status: UserStatus.ACTIVE },
      }),
      this.prisma.user.count({
        where: { deletedAt: null, status: UserStatus.BLOCKED },
      }),
      this.prisma.user.count({
        where: { deletedAt: null, createdAt: { gte: todayStart } },
      }),
      this.prisma.user.count({
        where: {
          deletedAt: null,
          OR: [
            { profile: null },
            { profile: { isProfileComplete: false } },
          ],
        },
      }),
      this.prisma.userSubscription.count({
        where: {
          status: 'ACTIVE',
          endDate: { gt: now },
          plan: { name: { not: 'FREE' } },
        },
      }),
    ]);

    return {
      totalUsers,
      activeUsers,
      blockedUsers,
      registeredToday,
      incompleteProfiles,
      premiumMembers,
    };
  }

  /**
   * Comprehensive user details with tabs for the Admin User Details view.
   */
  async getUserDetails(userId: string) {
    const now = new Date();
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: {
        profile: true,
        photos: {
          orderBy: [{ isPrimary: 'desc' }, { order: 'asc' }],
        },
        subscriptions: {
          orderBy: { createdAt: 'desc' },
          include: {
            plan: true,
            planVersion: true,
            payments: {
              orderBy: { createdAt: 'desc' },
            },
          },
        },
        partnerPreference: true,
        astrologyProfile: true,
        faceVerification: true,
        kycVerifications: {
          orderBy: { createdAt: 'desc' },
          take: 5,
        },
        memberNotes: {
          orderBy: { createdAt: 'desc' },
        },
        supportTickets: {
          orderBy: { createdAt: 'desc' },
          take: 10,
        },
        trustScoreLogs: {
          orderBy: { createdAt: 'desc' },
          take: 10,
        },
        _count: {
          select: {
            blocksMade: true,
            blocksReceived: true,
            reportsMade: true,
            reportsAgainst: true,
          },
        },
      },
    });

    if (!user || user.deletedAt) {
      throw new NotFoundException('Member account not found or deleted.');
    }

    const profile = user.profile;
    const age = profile?.dob ? ageOnIstDate(profile.dob, now) : null;
    const activeSub =
      user.subscriptions.find(
        (s) => s.status === 'ACTIVE' && s.endDate > now,
      ) ?? null;

    // Masked contact details (default presentation)
    const phoneMasked = user.phone ? maskPhone(user.phone) : null;
    const emailMasked = user.email.endsWith('@firebase.invalid')
      ? null
      : maskEmailForDisplay(user.email);

    return {
      id: user.id,
      firebaseUid: user.firebaseUid,
      status: user.status,
      role: user.role,
      trustScore: user.trustScore,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,

      basicInfo: {
        fullName: profile
          ? `${profile.firstName} ${profile.lastName}`.trim()
          : null,
        firstName: profile?.firstName ?? null,
        lastName: profile?.lastName ?? null,
        dob: profile?.dob ?? null,
        age,
        gender: profile?.gender ?? null,
        maritalStatus: profile?.maritalStatus ?? null,
        religion: profile?.religion ?? null,
        caste: profile?.caste ?? null,
        subCaste: profile?.subCaste ?? null,
        community: profile?.community ?? null,
        motherTongue: profile?.motherTongue ?? null,
        languagesKnown: profile?.languagesKnown ?? [],
        heightCm: profile?.heightCm ?? null,
        weightKg: profile?.weightKg ?? null,
        isProfileComplete: profile?.isProfileComplete ?? false,
        profileCompletePct: profile?.profileCompletePct ?? 0,
        bio: profile?.bio ?? null,
        profileCreatedAt: profile?.createdAt ?? null,
        profileUpdatedAt: profile?.updatedAt ?? null,
      },

      contactInfo: {
        phone: phoneMasked,
        email: emailMasked,
        isPhoneMasked: true,
        isEmailMasked: true,
        currentCity: profile?.currentCity ?? null,
        currentState: profile?.currentState ?? null,
        country: profile?.country ?? null,
        nativeCity: profile?.nativeCity ?? null,
        area: profile?.area ?? null,
        pinCode: profile?.pinCode ?? null,
      },

      careerAndFamily: {
        highestEducation: profile?.highestEducation ?? null,
        college: profile?.college ?? null,
        educationDetails: profile?.educationDetails ?? null,
        profession: profile?.profession ?? null,
        employerName: profile?.employerName ?? null,
        workIndustry: profile?.workIndustry ?? null,
        annualIncomeLakhs: profile?.annualIncomeLakhs
          ? Number(profile.annualIncomeLakhs)
          : null,
        familyType: profile?.familyType ?? null,
        familyValues: profile?.familyValues ?? null,
        familyStatus: profile?.familyStatus ?? null,
        fatherOccupation: profile?.fatherOccupation ?? null,
        motherOccupation: profile?.motherOccupation ?? null,
        siblings: profile?.siblings ?? 0,
        siblingDetails: profile?.siblingDetails ?? [],
        dietaryHabits: profile?.dietaryHabits ?? null,
        smokingHabits: profile?.smokingHabits ?? null,
        drinkingHabits: profile?.drinkingHabits ?? null,
      },

      partnerPreferences: user.partnerPreference
        ? {
            minAge: user.partnerPreference.minAge,
            maxAge: user.partnerPreference.maxAge,
            minHeightCm: user.partnerPreference.minHeightCm,
            maxHeightCm: user.partnerPreference.maxHeightCm,
            preferredReligions: user.partnerPreference.preferredReligions,
            preferredCastes: user.partnerPreference.preferredCastes,
            minIncomeLakhs: user.partnerPreference.minIncomeLakhs
              ? Number(user.partnerPreference.minIncomeLakhs)
              : null,
            preferredCities: user.partnerPreference.preferredCities,
            preferredStates: user.partnerPreference.preferredStates,
          }
        : null,

      astrologyProfile: user.astrologyProfile
        ? {
            rasi: user.astrologyProfile.rasi,
            nakshatra: user.astrologyProfile.nakshatra,
            dosham: user.astrologyProfile.dosham,
            lagnam: user.astrologyProfile.lagnam,
            gotram: user.astrologyProfile.gotram,
            birthDate: user.astrologyProfile.birthDate,
            birthTime: user.astrologyProfile.birthTime,
            birthPlace: user.astrologyProfile.birthPlace,
          }
        : null,

      membership: {
        currentPlan: activeSub?.plan?.displayName || activeSub?.plan?.name || 'Free',
        currentPlanCode: activeSub?.plan?.name || 'FREE',
        subscriptionStatus: activeSub?.status || 'INACTIVE',
        startDate: activeSub?.startDate || null,
        expiryDate: activeSub?.endDate || null,
        autoRenew: activeSub?.autoRenew ?? false,
        history: user.subscriptions.map((s) => ({
          id: s.id,
          planName: s.plan.displayName || s.plan.name,
          planCode: s.plan.name,
          tier: s.plan.tier,
          status: s.status,
          startDate: s.startDate,
          endDate: s.endDate,
          autoRenew: s.autoRenew,
          createdAt: s.createdAt,
          payments: s.payments.map((p) => ({
            id: p.id,
            amountInr: p.amountInr,
            currency: p.currency,
            status: p.status,
            paidAt: p.paidAt,
            createdAt: p.createdAt,
          })),
        })),
      },

      photosAndMedia: {
        primaryPhotoUrl:
          user.photos.find((p) => p.isPrimary)?.cdnUrl ?? null,
        photos: user.photos.map((p) => ({
          id: p.id,
          cdnUrl: p.cdnUrl,
          isPrimary: p.isPrimary,
          order: p.order,
          isApproved: p.isApproved,
          createdAt: p.createdAt,
        })),
        verification: {
          faceVerified: user.faceVerification?.status === 'VERIFIED',
          faceVerificationStatus: user.faceVerification?.status ?? 'UNVERIFIED',
          kycVerifications: user.kycVerifications.map((k) => ({
            id: k.id,
            docType: k.docType,
            status: k.status,
            rejectionReason: k.rejectionReason,
            createdAt: k.createdAt,
          })),
        },
      },

      internalNotes: user.memberNotes.map((n) => ({
        id: n.id,
        authorId: n.authorId,
        authorName: n.authorName || 'Staff',
        note: n.note,
        createdAt: n.createdAt,
        updatedAt: n.updatedAt,
      })),

      supportTickets: user.supportTickets.map((t) => ({
        id: t.id,
        type: t.type,
        subject: t.subject,
        status: t.status,
        adminResponse: t.adminResponse,
        createdAt: t.createdAt,
      })),

      accountActivity: {
        registrationDate: user.createdAt,
        lastProfileUpdate: profile?.updatedAt ?? user.updatedAt,
        trustScore: user.trustScore,
        trustScoreHistory: user.trustScoreLogs,
        blocksMadeCount: user._count.blocksMade,
        blocksReceivedCount: user._count.blocksReceived,
        reportsMadeCount: user._count.reportsMade,
        reportsAgainstCount: user._count.reportsAgainst,
      },
    };
  }

  /**
   * Block a user.
   * Updates status to BLOCKED, records audit log in the same transaction,
   * and clears the Redis auth-user cache so requests are refused immediately.
   */
  async blockUser(
    userId: string,
    admin: AuthenticatedAdmin,
    reason: string,
    context?: AdminRequestContext,
  ) {
    if (!reason || reason.trim().length < 3) {
      throw new BadRequestException('A reason of at least 3 characters is required to block a user.');
    }

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, status: true, firebaseUid: true, deletedAt: true },
    });

    if (!user || user.deletedAt) {
      throw new NotFoundException('User not found or deleted.');
    }

    if (user.status === UserStatus.BLOCKED) {
      throw new ConflictException('User is already blocked.');
    }

    const previousStatus = user.status;

    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: { status: UserStatus.BLOCKED },
      });

      await this.auditService.record(tx, {
        actorId: admin.userId,
        actorType: 'STAFF',
        action: 'member.block',
        entity: 'User',
        entityId: userId,
        reason: reason.trim(),
        before: { status: previousStatus },
        after: { status: UserStatus.BLOCKED },
        context,
      });
    });

    // Invalidate auth cache so the very next user request returns 403 Forbidden
    await invalidateCachedUserId(this.redis, user.firebaseUid);

    return {
      success: true,
      userId,
      previousStatus,
      status: UserStatus.BLOCKED,
      reason: reason.trim(),
    };
  }

  /**
   * Unblock a user.
   * Restores status to ACTIVE, records audit log, and invalidates Redis cache.
   */
  async unblockUser(
    userId: string,
    admin: AuthenticatedAdmin,
    context?: AdminRequestContext,
    reason?: string,
  ) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, status: true, firebaseUid: true, deletedAt: true },
    });

    if (!user || user.deletedAt) {
      throw new NotFoundException('User not found or deleted.');
    }

    if (user.status !== UserStatus.BLOCKED) {
      throw new BadRequestException(
        `User is not blocked (current status: ${user.status}).`,
      );
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: { status: UserStatus.ACTIVE },
      });

      await this.auditService.record(tx, {
        actorId: admin.userId,
        actorType: 'STAFF',
        action: 'member.unblock',
        entity: 'User',
        entityId: userId,
        reason: reason?.trim() || 'Admin unblocked user',
        before: { status: UserStatus.BLOCKED },
        after: { status: UserStatus.ACTIVE },
        context,
      });
    });

    await invalidateCachedUserId(this.redis, user.firebaseUid);

    return {
      success: true,
      userId,
      previousStatus: UserStatus.BLOCKED,
      status: UserStatus.ACTIVE,
    };
  }

  /**
   * Reveal sensitive PII (unmasked phone and email).
   * Records a sensitive audit entry (`member.pii.reveal`).
   */
  async revealPii(
    userId: string,
    admin: AuthenticatedAdmin,
    context?: AdminRequestContext,
    reason?: string,
  ) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        phone: true,
        deletedAt: true,
        profile: {
          select: {
            currentCity: true,
            currentState: true,
            country: true,
            pinCode: true,
          },
        },
      },
    });

    if (!user || user.deletedAt) {
      throw new NotFoundException('User not found or deleted.');
    }

    // Record the PII access in audit logs
    await this.auditService.recordBestEffort({
      actorId: admin.userId,
      actorType: 'STAFF',
      action: 'member.pii.reveal',
      entity: 'User',
      entityId: userId,
      reason: reason?.trim() || 'Admin revealed member PII',
      metadata: { targetUserId: userId },
      context,
    });

    return {
      userId: user.id,
      email: user.email.endsWith('@firebase.invalid') ? null : user.email,
      phone: user.phone,
      location: user.profile
        ? {
            city: user.profile.currentCity,
            state: user.profile.currentState,
            country: user.profile.country,
            pinCode: user.profile.pinCode,
          }
        : null,
    };
  }

  /**
   * Add internal staff note to a user's profile.
   */
  async addNote(
    userId: string,
    admin: AuthenticatedAdmin,
    note: string,
  ) {
    if (!note?.trim()) {
      throw new BadRequestException('Note content cannot be empty.');
    }

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, deletedAt: true },
    });

    if (!user || user.deletedAt) {
      throw new NotFoundException('User not found or deleted.');
    }

    const created = await this.prisma.memberNote.create({
      data: {
        userId,
        authorId: admin.userId,
        authorName: admin.email,
        note: note.trim(),
      },
    });

    return {
      id: created.id,
      userId: created.userId,
      authorId: created.authorId,
      authorName: created.authorName,
      note: created.note,
      createdAt: created.createdAt,
    };
  }
}
