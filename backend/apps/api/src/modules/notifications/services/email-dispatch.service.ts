import { Injectable, Logger } from '@nestjs/common';
import { AppConfigService } from '@app/config';
import { MailService } from '@app/mail';
import { PrismaService } from '@app/database';

/**
 * Turns "this happened to user X" into a queued email.
 *
 * Sibling of PushDispatchService, and the same contract: domain services call
 * it AFTER their transaction commits, and it never throws back at them. A
 * member's interest or message must not fail because an email could not be
 * queued.
 *
 * It exists so callers pass user ids, not addresses — recipient lookup,
 * eligibility and suppression live in one place instead of being repeated (and
 * eventually diverging) across ProfileService, InterestsService and
 * MessagesService.
 *
 * Reads Prisma directly rather than going through a repository: this is a
 * single narrow projection (email + display fields) used only here, and
 * routing it through NotificationRepository would widen that repository's
 * responsibility for no benefit.
 */
@Injectable()
export class EmailDispatchService {
  private readonly logger = new Logger(EmailDispatchService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly mail: MailService,
    private readonly configService: AppConfigService,
  ) {}

  /** Sent once, when a member finishes the registration wizard. */
  async sendWelcome(userId: string): Promise<void> {
    await this.safely('welcome', userId, async () => {
      const user = await this.findRecipient(userId);
      if (!user) return;

      await this.mail.sendWelcome(user.email, {
        firstName: user.firstName,
        userId,
      });
    });
  }

  /**
   * Sent to the original sender when their interest is accepted — the moment a
   * one-way interest becomes a mutual match, which is the event members
   * actually care about. Not sent on a plain interest-received: that would mail
   * on every inbound tap and train people to filter us out.
   */
  async sendMatchFound(
    recipientUserId: string,
    matchUserId: string,
  ): Promise<void> {
    await this.safely('match-found', recipientUserId, async () => {
      const [recipient, match] = await Promise.all([
        this.findRecipient(recipientUserId),
        this.findRecipient(matchUserId),
      ]);
      if (!recipient || !match) return;

      await this.mail.sendMatchFound(recipient.email, {
        firstName: recipient.firstName,
        matchName: match.firstName,
        matchAge: match.age ?? '',
        matchCity: match.city ?? '',
        matchProfession: match.profession ?? '',
        matchProfileUrl: `${this.appUrl}/profile/${matchUserId}`,
        userId: recipientUserId,
      });
    });
  }

  /**
   * Sent to the recipient of a chat message.
   *
   * `preview` is the raw message body; MailService truncates it. Callers must
   * only pass plain-text message types — never a signed attachment URL, which
   * would end up in an email that outlives the URL's expiry.
   */
  async sendNewMessage(
    recipientUserId: string,
    senderUserId: string,
    preview: string,
    conversationId: string,
  ): Promise<void> {
    await this.safely('new-message', recipientUserId, async () => {
      const [recipient, sender] = await Promise.all([
        this.findRecipient(recipientUserId),
        this.findRecipient(senderUserId),
      ]);
      if (!recipient || !sender) return;

      await this.mail.sendNewMessage(recipient.email, {
        senderName: sender.firstName,
        messagePreview: preview,
        conversationUrl: `${this.appUrl}/chat/${conversationId}`,
        userId: recipientUserId,
      });
    });
  }

  private get appUrl(): string {
    return this.configService.mail.appUrl.replace(/\/+$/, '');
  }

  /**
   * Loads the fields templates need, and enforces eligibility in the query:
   * a soft-deleted or banned member is never mailed. Returns undefined when
   * there is nothing sendable — including a user with no finalized profile,
   * since every template addresses people by first name.
   */
  private async findRecipient(userId: string) {
    const user = await this.prisma.user.findFirst({
      where: {
        id: userId,
        deletedAt: null,
        status: { notIn: ['BANNED', 'DEACTIVATED'] },
      },
      select: {
        email: true,
        profile: {
          select: {
            firstName: true,
            dob: true,
            currentCity: true,
            profession: true,
          },
        },
      },
    });

    if (!user?.email || !user.profile) return undefined;

    return {
      email: user.email,
      firstName: user.profile.firstName,
      age: ageFrom(user.profile.dob),
      city: user.profile.currentCity,
      profession: user.profile.profession,
    };
  }

  /**
   * Swallows and logs. Mirrors PushDispatchService.dispatchToUser — the domain
   * write has already committed by the time we get here, so throwing would
   * fail a request whose real work succeeded.
   */
  private async safely(
    kind: string,
    userId: string,
    run: () => Promise<void>,
  ): Promise<void> {
    try {
      await run();
    } catch (error) {
      this.logger.error(
        `Email dispatch "${kind}" failed for user ${userId}: ${(error as Error).message}`,
      );
    }
  }
}

/** Whole years, the way a profile card displays age. */
export function ageFrom(dob: Date): number {
  const now = new Date();
  let age = now.getFullYear() - dob.getFullYear();
  const monthDelta = now.getMonth() - dob.getMonth();
  if (monthDelta < 0 || (monthDelta === 0 && now.getDate() < dob.getDate())) {
    age--;
  }
  return age;
}
