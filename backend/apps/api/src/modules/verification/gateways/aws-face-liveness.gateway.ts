import { Injectable, Logger } from '@nestjs/common';
import {
  CompareFacesCommand,
  CreateFaceLivenessSessionCommand,
  GetFaceLivenessSessionResultsCommand,
  RekognitionClient,
} from '@aws-sdk/client-rekognition';
import { AssumeRoleCommand, STSClient } from '@aws-sdk/client-sts';
import { AppConfigService } from '@app/config';
import { LIVENESS_CLIENT_SESSION_POLICY } from '../domain/face-verification.constants';
import type {
  CompareFacesResult,
  FaceLivenessGateway,
  LivenessSessionResult,
  TemporaryAwsCredentials,
} from './face-liveness.gateway';

/**
 * AWS Rekognition + STS implementation of [FaceLivenessGateway].
 *
 * Authenticates as the dedicated face-verification backend IAM identity
 * (FACE_VERIFICATION_AWS_*) — never the S3 credentials. Clients are only built
 * when that identity AND the client role ARN are configured; otherwise the
 * gateway reports `isConfigured() === false` and FaceVerificationService
 * answers 503 before any method here is reached. Constructing the SDK clients
 * makes no network call, so the app boots identically with or without AWS.
 *
 * Images travel as raw bytes: no Rekognition S3 output location, so AWS
 * writes nothing into the bucket and the backend identity needs no S3 access.
 */
@Injectable()
export class AwsFaceLivenessGateway implements FaceLivenessGateway {
  private readonly logger = new Logger(AwsFaceLivenessGateway.name);
  private readonly rekognition: RekognitionClient | null;
  private readonly sts: STSClient | null;

  constructor(private readonly config: AppConfigService) {
    const { region, accessKeyId, secretAccessKey, clientRoleArn } =
      this.config.faceVerification;

    if (region && accessKeyId && secretAccessKey && clientRoleArn) {
      const credentials = { accessKeyId, secretAccessKey };
      this.rekognition = new RekognitionClient({ region, credentials });
      this.sts = new STSClient({ region, credentials });
      this.logger.log(
        `Face verification AWS gateway ready (region="${region}").`,
      );
    } else {
      this.rekognition = null;
      this.sts = null;
    }
  }

  isConfigured(): boolean {
    return this.rekognition !== null && this.sts !== null;
  }

  region(): string {
    return this.config.faceVerification.region;
  }

  async createLivenessSession(clientRequestToken: string): Promise<string> {
    const response = await this.requireRekognition().send(
      new CreateFaceLivenessSessionCommand({
        ClientRequestToken: clientRequestToken,
        // No OutputConfig: reference/audit images are returned inline to the
        // backend only and never written to S3. No audit images at all.
        Settings: { AuditImagesLimit: 0 },
      }),
    );
    if (!response.SessionId) {
      throw new Error('CreateFaceLivenessSession returned no SessionId.');
    }
    return response.SessionId;
  }

  async getLivenessSessionResults(
    sessionId: string,
  ): Promise<LivenessSessionResult> {
    const response = await this.requireRekognition().send(
      new GetFaceLivenessSessionResultsCommand({ SessionId: sessionId }),
    );
    return {
      status: response.Status ?? 'UNKNOWN',
      confidence: response.Confidence,
      referenceImage: response.ReferenceImage?.Bytes,
    };
  }

  async compareFaces(
    source: Uint8Array,
    target: Uint8Array,
  ): Promise<CompareFacesResult> {
    const response = await this.requireRekognition().send(
      new CompareFacesCommand({
        SourceImage: { Bytes: source },
        TargetImage: { Bytes: target },
        // 0 so every detected target face is returned with its similarity:
        // the backend applies its own configured threshold AND needs the
        // full face count for the exactly-one-face rule.
        SimilarityThreshold: 0,
        // Let Rekognition drop non-faces / extreme blur, so a stray
        // background artefact is not counted as a second person.
        QualityFilter: 'AUTO',
      }),
    );
    const matches = response.FaceMatches ?? [];
    const unmatched = response.UnmatchedFaces ?? [];
    const similarities = matches
      .map((m) => m.Similarity)
      .filter((s): s is number => typeof s === 'number');
    return {
      faceCount: matches.length + unmatched.length,
      bestSimilarity:
        similarities.length > 0 ? Math.max(...similarities) : undefined,
    };
  }

  async issueClientCredentials(
    sessionName: string,
  ): Promise<TemporaryAwsCredentials> {
    const sts = this.sts;
    const { clientRoleArn, credentialsTtlSeconds } =
      this.config.faceVerification;
    if (!sts || !clientRoleArn) {
      throw new Error('Face verification STS is not configured.');
    }
    const response = await sts.send(
      new AssumeRoleCommand({
        RoleArn: clientRoleArn,
        RoleSessionName: sessionName,
        DurationSeconds: credentialsTtlSeconds,
        // Session policy: the resulting credentials are the intersection of
        // the role's policy and this — StartFaceLivenessSession only.
        Policy: JSON.stringify(LIVENESS_CLIENT_SESSION_POLICY),
      }),
    );
    const c = response.Credentials;
    if (
      !c?.AccessKeyId ||
      !c.SecretAccessKey ||
      !c.SessionToken ||
      !c.Expiration
    ) {
      throw new Error('AssumeRole returned incomplete credentials.');
    }
    return {
      accessKeyId: c.AccessKeyId,
      secretAccessKey: c.SecretAccessKey,
      sessionToken: c.SessionToken,
      expiration: c.Expiration,
    };
  }

  private requireRekognition(): RekognitionClient {
    if (!this.rekognition) {
      throw new Error(
        'Face verification Rekognition client is not configured.',
      );
    }
    return this.rekognition;
  }
}
