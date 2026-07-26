import {
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  CurrentUser,
  FirebaseAuthGuard,
  PaginationQueryDto,
} from '@app/common';
import { InterestsService } from '../services/interests.service';
import { InterestListItemDto } from '../dto/interest-response.dto';

// Read/withdraw side of Interests. The write side (send / accept / decline)
// lives on MatchesController at POST /matches/interest, matching the frontend
// contract (one write endpoint, reused). Every route is user-scoped via the
// verified Firebase token.
@Controller('interests')
@UseGuards(FirebaseAuthGuard)
export class InterestsController {
  constructor(private readonly interestsService: InterestsService) {}

  /** GET /interests/received — interests others sent to me, newest first. Each
   *  item carries the *sender's* profile card. */
  @Get('received')
  received(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<InterestListItemDto[]> {
    return this.interestsService.listReceived(userId, pagination);
  }

  /** GET /interests/sent — interests I sent, newest first. Each item carries
   *  the *receiver's* profile card. */
  @Get('sent')
  sent(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<InterestListItemDto[]> {
    return this.interestsService.listSent(userId, pagination);
  }

  /** DELETE /interests/:id — withdraw a pending interest I sent. */
  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  withdraw(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ): Promise<void> {
    return this.interestsService.withdraw(userId, id);
  }
}
