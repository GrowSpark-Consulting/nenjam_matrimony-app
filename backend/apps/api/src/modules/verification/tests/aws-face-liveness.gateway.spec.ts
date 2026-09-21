import {
  CompareFacesCommand,
  CreateFaceLivenessSessionCommand,
  GetFaceLivenessSessionResultsCommand,
  RekognitionClient,
} from '@aws-sdk/client-rekognition';
import { AssumeRoleCommand, STSClient } from '@aws-sdk/client-sts';
import type { AppConfigService } from '@app/config';
import { AwsFaceLivenessGateway } from '../gateways/aws-face-liveness.gateway';
import { awsErrorName } from '../gateways/face-liveness.gateway';
import { LIVENESS_CLIENT_SESSION_POLICY } from '../domain/face-verification.constants';

// No real AWS call is ever made here: `send` on both SDK clients is replaced
// before any command is issued, and the credentials are obviously fake.
const ROLE_ARN = 'arn:aws:iam::123456789012:role/nenjam-face-liveness-client';

/** The command passed to the n-th `send` call on a spied SDK client. */
function sentCommand<T>(spy: jest.SpyInstance, call = 0): T {
  return (spy.mock.calls as unknown[][])[call][0] as T;
}

function makeConfig(
  overrides: Partial<AppConfigService['faceVerification']> = {},
): AppConfigService {
  return {
    faceVerification: {
      enabled: true,
      region: 'ap-south-1',
      accessKeyId: 'test-backend-access-key-id',
      secretAccessKey: 'fake-secret',
      clientRoleArn: ROLE_ARN,
      credentialsTtlSeconds: 900,
      minLivenessConfidence: 90,
      minMatchSimilarity: 90,
      maxAttemptsPerDay: 3,
      globalDailyCap: 500,
      ...overrides,
    },
  } as unknown as AppConfigService;
}

describe('AwsFaceLivenessGateway', () => {
  // `send` is heavily overloaded (promise + callback forms); spy on it through
  // a plain promise-returning signature so resolved/rejected values type-check.
  type SendSpy = jest.SpyInstance<Promise<unknown>, unknown[]>;
  let rekognitionSend: SendSpy;
  let stsSend: SendSpy;

  beforeEach(() => {
    rekognitionSend = (
      jest.spyOn(RekognitionClient.prototype, 'send') as unknown as SendSpy
    ).mockRejectedValue(new Error('unexpected call'));
    stsSend = (
      jest.spyOn(STSClient.prototype, 'send') as unknown as SendSpy
    ).mockRejectedValue(new Error('unexpected call'));
  });

  afterEach(() => jest.restoreAllMocks());

  it('is not configured (and never calls AWS) without every AWS value', async () => {
    for (const missing of [
      'accessKeyId',
      'secretAccessKey',
      'clientRoleArn',
    ] as const) {
      const gateway = new AwsFaceLivenessGateway(
        makeConfig({ [missing]: undefined }),
      );
      expect(gateway.isConfigured()).toBe(false);
      await expect(gateway.createLivenessSession('t')).rejects.toThrow(
        /not configured/,
      );
      await expect(gateway.issueClientCredentials('s')).rejects.toThrow(
        /not configured/,
      );
    }
    expect(rekognitionSend).not.toHaveBeenCalled();
    expect(stsSend).not.toHaveBeenCalled();
  });

  it('creates an idempotent session with no S3 output and no audit images', async () => {
    rekognitionSend.mockResolvedValueOnce({ SessionId: 'session-1' });
    const gateway = new AwsFaceLivenessGateway(makeConfig());

    await expect(gateway.createLivenessSession('attempt-1')).resolves.toBe(
      'session-1',
    );

    const command =
      sentCommand<CreateFaceLivenessSessionCommand>(rekognitionSend);
    expect(command).toBeInstanceOf(CreateFaceLivenessSessionCommand);
    expect(command.input).toEqual({
      ClientRequestToken: 'attempt-1',
      Settings: { AuditImagesLimit: 0 },
    });
  });

  it('maps session results, keeping the reference image in memory only', async () => {
    const reference = new Uint8Array([1, 2, 3]);
    rekognitionSend.mockResolvedValueOnce({
      Status: 'SUCCEEDED',
      Confidence: 98.2,
      ReferenceImage: { Bytes: reference },
    });
    const gateway = new AwsFaceLivenessGateway(makeConfig());

    const result = await gateway.getLivenessSessionResults('session-1');

    expect(result).toEqual({
      status: 'SUCCEEDED',
      confidence: 98.2,
      referenceImage: reference,
    });
    const command =
      sentCommand<GetFaceLivenessSessionResultsCommand>(rekognitionSend);
    expect(command).toBeInstanceOf(GetFaceLivenessSessionResultsCommand);
    expect(command.input).toEqual({ SessionId: 'session-1' });
  });

  it('compares raw bytes with threshold 0 and counts every target face', async () => {
    rekognitionSend.mockResolvedValueOnce({
      FaceMatches: [{ Similarity: 72.4 }, { Similarity: 96.1 }],
      UnmatchedFaces: [{}],
    });
    const gateway = new AwsFaceLivenessGateway(makeConfig());
    const source = new Uint8Array([9]);
    const target = new Uint8Array([8]);

    await expect(gateway.compareFaces(source, target)).resolves.toEqual({
      faceCount: 3,
      bestSimilarity: 96.1,
    });
    const command = sentCommand<CompareFacesCommand>(rekognitionSend);
    expect(command).toBeInstanceOf(CompareFacesCommand);
    expect(command.input).toEqual({
      SourceImage: { Bytes: source },
      TargetImage: { Bytes: target },
      SimilarityThreshold: 0,
      QualityFilter: 'AUTO',
    });
  });

  it('reports no similarity when the photo has no face match', async () => {
    rekognitionSend.mockResolvedValueOnce({
      FaceMatches: [],
      UnmatchedFaces: [],
    });
    const gateway = new AwsFaceLivenessGateway(makeConfig());
    await expect(
      gateway.compareFaces(new Uint8Array([1]), new Uint8Array([2])),
    ).resolves.toEqual({ faceCount: 0, bestSimilarity: undefined });
  });

  it('mints StartFaceLivenessSession-only credentials for the configured TTL', async () => {
    const expiration = new Date('2026-09-21T10:15:00Z');
    stsSend.mockResolvedValueOnce({
      Credentials: {
        AccessKeyId: 'ASIATEMP',
        SecretAccessKey: 'temp-secret',
        SessionToken: 'temp-token',
        Expiration: expiration,
      },
    });
    const gateway = new AwsFaceLivenessGateway(makeConfig());

    await expect(
      gateway.issueClientCredentials('nenjam-fv-attempt-1'),
    ).resolves.toEqual({
      accessKeyId: 'ASIATEMP',
      secretAccessKey: 'temp-secret',
      sessionToken: 'temp-token',
      expiration,
    });

    const command = sentCommand<AssumeRoleCommand>(stsSend);
    expect(command).toBeInstanceOf(AssumeRoleCommand);
    expect(command.input.RoleArn).toBe(ROLE_ARN);
    expect(command.input.RoleSessionName).toBe('nenjam-fv-attempt-1');
    expect(command.input.DurationSeconds).toBe(900);
    expect(JSON.parse(command.input.Policy as string)).toEqual(
      LIVENESS_CLIENT_SESSION_POLICY,
    );
    // The permanent backend key never appears in what is requested or returned.
    expect(JSON.stringify(command.input)).not.toContain(
      'test-backend-access-key-id',
    );
  });

  it('rejects an incomplete STS response rather than handing out partial credentials', async () => {
    stsSend.mockResolvedValueOnce({ Credentials: { AccessKeyId: 'ASIATEMP' } });
    const gateway = new AwsFaceLivenessGateway(makeConfig());
    await expect(gateway.issueClientCredentials('s')).rejects.toThrow(
      /incomplete/,
    );
  });

  it('names AWS errors for classification', () => {
    const error = Object.assign(new Error('x'), {
      name: 'SessionNotFoundException',
    });
    expect(awsErrorName(error)).toBe('SessionNotFoundException');
    expect(awsErrorName(null)).toBe('Error');
    expect(awsErrorName({})).toBe('Error');
  });
});
