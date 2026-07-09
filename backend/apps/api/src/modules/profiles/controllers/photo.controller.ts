import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { PhotoService } from '../services/photo.service';
import { PhotoUploadDto } from '../dto/photo-upload.dto';
import { PhotoEntity } from '../entities/photo.entity';

// Wizard step 11 (Photos). Actual file transfer to S3 isn't wired yet (see
// libs/storage) — this registers metadata for a photo the client already
// uploaded via some other means (e.g. a presigned URL once that's built).
@Controller('profiles/me/photos')
@UseGuards(FirebaseAuthGuard)
export class PhotoController {
  constructor(private readonly photoService: PhotoService) {}

  @Get()
  list(@CurrentUser('id') userId: string): Promise<PhotoEntity[]> {
    return this.photoService.list(userId);
  }

  @Post()
  register(
    @CurrentUser('id') userId: string,
    @Body() dto: PhotoUploadDto,
  ): Promise<PhotoEntity> {
    return this.photoService.register(userId, dto);
  }
}
