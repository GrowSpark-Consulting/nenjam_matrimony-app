import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { StorageModule } from '@app/storage';
import { FaceVerificationController } from './controllers/face-verification.controller';
import { FaceVerificationService } from './services/face-verification.service';
import { FaceVerificationRepository } from './repositories/face-verification.repository';
import { FACE_LIVENESS_GATEWAY } from './gateways/face-liveness.gateway';
import { AwsFaceLivenessGateway } from './gateways/aws-face-liveness.gateway';

/**
 * Verification. Today this wires face verification only (AWS Face Liveness +
 * CompareFaces). The document-verification stubs beside it
 * (VerificationController/Service, SubmitDocumentDto, ...) are intentionally
 * NOT registered: they are still empty, and registering them would change
 * nothing but the route table.
 *
 * PrismaService, RedisService and FirebaseService are global (FirebaseAuthGuard
 * resolves them); StorageModule provides S3Service for reading the profile
 * photo; AppConfigModule provides AppConfigService, as in StorageModule.
 *
 * The AWS gateway is bound by token so tests substitute a fake and nothing
 * here ever needs real AWS credentials to compile, boot or be tested.
 */
@Module({
  imports: [AppConfigModule, StorageModule],
  controllers: [FaceVerificationController],
  providers: [
    FaceVerificationService,
    FaceVerificationRepository,
    { provide: FACE_LIVENESS_GATEWAY, useClass: AwsFaceLivenessGateway },
  ],
})
export class VerificationModule {}
