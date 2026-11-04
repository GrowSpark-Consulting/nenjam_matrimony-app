/**
 * `AgentClientMemberProfilePort` over the member side's own
 * `ProfileService.syncMatchableFromDraft`: the same call every member's
 * registration save makes once the mandatory answers are in. It writes her
 * `user_profiles` row (and the astrology and partner-preference rows the
 * draft has answers for) from the registration draft accept created, so
 * `GET /profiles/me` answers 200 and the member app opens the home page.
 * Nothing about visibility is decided here: the row is exactly what a
 * member's own save produces.
 *
 * Not in a transaction: it runs after the accept has committed.
 */
import type { PrismaClient } from '@app/database';
import type { ProfileService } from '../../../profiles/services/profile.service';
import type { AgentClientMemberProfilePort } from '../../ports/agent-client-ports';

export class MemberProfileFromDraft implements AgentClientMemberProfilePort {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly profiles: Pick<ProfileService, 'syncMatchableFromDraft'>,
  ) {}

  async exists(memberId: string): Promise<boolean> {
    const row = await this.prisma.userProfile.findUnique({
      where: { userId: memberId },
      select: { userId: true },
    });
    return row !== null;
  }

  createFromDraft(memberId: string): Promise<void> {
    return this.profiles.syncMatchableFromDraft(memberId);
  }
}
