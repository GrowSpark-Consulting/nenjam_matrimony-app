import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { UPLOAD_LIMIT } from '../../../throttling';
import { FileInterceptor } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { PhotoService } from '../services/photo.service';
import { PhotoUploadDto } from '../dto/photo-upload.dto';
import { ReorderPhotosDto } from '../dto/reorder-photos.dto';
import { PhotoEntity } from '../entities/photo.entity';
import { PhotoFilePipe } from '../pipes/photo-file.pipe';
import type { UploadedImageFile } from '../pipes/photo-file.pipe';

// Profile photo management — every route is scoped to the authenticated user
// (FirebaseAuthGuard supplies the id), so a user can only ever read or mutate
// their own photos. Files are streamed into memory (never written to disk) and
// forwarded to S3 by PhotoService.
//
// A generous 15 MB multer hard cap guards against pathological memory use;
// the real product limit (5 MB, image types only) is enforced by
// PhotoFilePipe with a friendly 400.
const fileInterceptor = FileInterceptor('file', {
  storage: memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024, files: 1 },
});

@Controller('profiles/me/photos')
@UseGuards(FirebaseAuthGuard)
export class PhotoController {
  constructor(private readonly photoService: PhotoService) {}

  @Get()
  list(@CurrentUser('id') userId: string): Promise<PhotoEntity[]> {
    return this.photoService.list(userId);
  }

  // Each upload costs bandwidth and an S3 object, so this is the tightest
  // limit in the app.
  @Throttle(UPLOAD_LIMIT)
  @Post()
  @UseInterceptors(fileInterceptor)
  upload(
    @CurrentUser('id') userId: string,
    @UploadedFile(PhotoFilePipe) file: UploadedImageFile,
    @Body() dto: PhotoUploadDto,
  ): Promise<PhotoEntity> {
    return this.photoService.upload(userId, file, dto.isPrimary);
  }

  @Throttle(UPLOAD_LIMIT)
  @Put(':id')
  @UseInterceptors(fileInterceptor)
  replace(
    @CurrentUser('id') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @UploadedFile(PhotoFilePipe) file: UploadedImageFile,
  ): Promise<PhotoEntity> {
    return this.photoService.replace(userId, id, file);
  }

  @Patch('reorder')
  reorder(
    @CurrentUser('id') userId: string,
    @Body() dto: ReorderPhotosDto,
  ): Promise<PhotoEntity[]> {
    return this.photoService.reorder(userId, dto.photoIds);
  }

  @Patch(':id/primary')
  setPrimary(
    @CurrentUser('id') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<PhotoEntity[]> {
    return this.photoService.setPrimary(userId, id);
  }

  @Delete(':id')
  remove(
    @CurrentUser('id') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<PhotoEntity[]> {
    return this.photoService.remove(userId, id);
  }
}
