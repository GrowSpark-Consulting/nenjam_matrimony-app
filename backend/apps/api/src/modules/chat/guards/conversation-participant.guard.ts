import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Request } from 'express';
import type { AuthenticatedUser } from '@app/common';
import { ConversationRepository } from '../repositories/conversation.repository';

interface RequestWithUser extends Request {
  user?: AuthenticatedUser;
  params: { id?: string };
}

/**
 * Defense-in-depth for the `:id` conversation routes: rejects (403) anyone who
 * isn't one of the room's two participants, and 404s an unknown room — before
 * the handler runs. Must be applied AFTER FirebaseAuthGuard (which populates
 * `request.user`). Services still re-derive participation for their own logic;
 * this guarantees no `:id` route body ever executes for a non-participant.
 */
@Injectable()
export class ConversationParticipantGuard implements CanActivate {
  constructor(
    private readonly conversationRepository: ConversationRepository,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<RequestWithUser>();
    const userId = request.user?.id;
    const conversationId = request.params?.id;
    if (!userId || !conversationId) {
      throw new ForbiddenException('Conversation access denied.');
    }

    const room = await this.conversationRepository.findById(conversationId);
    if (!room) throw new NotFoundException('Conversation not found.');
    if (room.user1Id !== userId && room.user2Id !== userId) {
      throw new ForbiddenException(
        'You are not a participant in this conversation.',
      );
    }
    return true;
  }
}
