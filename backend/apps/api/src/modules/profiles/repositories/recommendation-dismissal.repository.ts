import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type { RecommendationCardKey } from '../domain/recommendation-cards';

/**
 * The `profile_recommendation_dismissals` table — "hide this suggestion",
 * and nothing else.
 *
 * There is deliberately no update path and no payload beyond the card key: a
 * dismissal cannot carry, mask or delete profile data, so the worst a bug
 * here can do is show or hide a card. Restoring one is a plain delete, which
 * is what makes "the member finished the section from somewhere else" a
 * non-event — the card disappears on `isComplete` regardless of whether a
 * dismissal row is still sitting there.
 */
@Injectable()
export class RecommendationDismissalRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** Every card key this member has dismissed. */
  async findKeysForUser(userId: string): Promise<string[]> {
    const rows = await this.prisma.profileRecommendationDismissal.findMany({
      where: { userId },
      select: { cardKey: true },
    });
    return rows.map((row) => row.cardKey);
  }

  /**
   * Idempotent — dismissing an already-dismissed card is a no-op rather than
   * a unique-constraint error, so a double tap or an offline retry is safe.
   */
  async dismiss(userId: string, cardKey: RecommendationCardKey): Promise<void> {
    await this.prisma.profileRecommendationDismissal.upsert({
      where: { userId_cardKey: { userId, cardKey } },
      create: { userId, cardKey },
      update: {},
    });
  }

  /**
   * Un-dismisses a card. `deleteMany` (not `delete`) so restoring a card that
   * was never dismissed succeeds silently instead of throwing P2025.
   */
  async restore(userId: string, cardKey: RecommendationCardKey): Promise<void> {
    await this.prisma.profileRecommendationDismissal.deleteMany({
      where: { userId, cardKey },
    });
  }
}
