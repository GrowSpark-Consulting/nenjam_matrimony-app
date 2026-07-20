import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { S3Service } from './s3.service';

// Imports AppConfigModule so S3Service can inject AppConfigService — matching
// the FirebaseModule pattern. (The `isGlobal` flag applies to the inner
// @nestjs/config module, not to the AppConfigService provider wrapper.)
@Module({
  imports: [AppConfigModule],
  providers: [S3Service],
  exports: [S3Service],
})
export class StorageModule {}
