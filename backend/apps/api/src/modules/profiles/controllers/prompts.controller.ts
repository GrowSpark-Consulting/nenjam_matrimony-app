import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Put,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { PromptsService } from '../services/prompts.service';
import { SavePromptsDto } from '../dto/save-prompts.dto';
import { PromptBankItemEntity } from '../entities/prompt-bank-item.entity';
import { UserProfilePromptEntity } from '../entities/user-profile-prompt.entity';

// Relationship Intelligence — Profile Prompts (Hinge/Jeevansathi-style).
// Independent of the registration wizard and its /profiles/draft/*
// endpoints, matching the frontend's own architecture decision (see
// Frontend/lib/features/profile_prompts/domain/repositories/
// profile_prompt_repository.dart).
@Controller('profiles/prompts')
@UseGuards(FirebaseAuthGuard)
export class PromptsController {
  constructor(private readonly promptsService: PromptsService) {}

  @Get('bank')
  getBank(): Promise<PromptBankItemEntity[]> {
    return this.promptsService.getBank();
  }

  @Get('me')
  getMine(
    @CurrentUser('id') userId: string,
  ): Promise<UserProfilePromptEntity[]> {
    return this.promptsService.getUserPrompts(userId);
  }

  // Replace-all save — matches ChoosePromptPage submitting its full current
  // selection (0-3 prompts) on every save, not one prompt at a time.
  @Put('me')
  saveMine(
    @CurrentUser('id') userId: string,
    @Body() dto: SavePromptsDto,
  ): Promise<UserProfilePromptEntity[]> {
    return this.promptsService.saveUserPrompts(userId, dto.prompts);
  }

  @Delete('me/:promptId')
  deleteMine(
    @CurrentUser('id') userId: string,
    @Param('promptId') promptId: string,
  ): Promise<void> {
    return this.promptsService.deletePrompt(userId, promptId);
  }
}
