import {
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  IdentifierHasher,
  type IdentifierKind,
  parseIdentifierPeppers,
} from '@app/common';
import { AppConfigService } from '@app/config';

/** 503 for any route that needs identifier hashing while it is not set up. */
export class IdentifierHashingUnavailableError extends ServiceUnavailableException {
  constructor() {
    super({
      statusCode: 503,
      error: 'Service Unavailable',
      code: 'IDENTIFIER_HASHING_UNAVAILABLE',
      message: 'This feature is not available yet.',
    });
  }
}

/**
 * `hashIdentifier(kind, value)` for the API: keyed, versioned hashes of
 * phones, emails, PANs and IPs (see `IdentifierHasher` in @app/common for the
 * normalisation rules). Store `hashIdentifier`; look up with
 * `hashIdentifierAll`, which also matches rows hashed before a pepper
 * rotation.
 *
 * Without IDENTIFIER_HASH_PEPPERS the app still boots and every call throws a
 * 503, so only the features that need hashing are off.
 */
@Injectable()
export class IdentifierHashService {
  private readonly logger = new Logger(IdentifierHashService.name);
  private readonly hasher: IdentifierHasher | null;

  constructor(config: AppConfigService) {
    const peppers = parseIdentifierPeppers(
      config.identifierHash.peppers,
      'IDENTIFIER_HASH_PEPPERS',
    );
    this.hasher = peppers ? new IdentifierHasher(peppers) : null;
    if (!this.hasher) {
      this.logger.warn(
        'IDENTIFIER_HASH_PEPPERS is not set: identifier hashing answers 503.',
      );
    }
  }

  get available(): boolean {
    return this.hasher !== null;
  }

  /** The hash to store, made with the newest pepper. Throws RangeError for
   *  an empty value or one that is not a phone / IP address. */
  hashIdentifier(kind: IdentifierKind, value: string): string {
    return this.requireHasher().hash(kind, value);
  }

  /** One hash per configured pepper, newest first: `WHERE hash IN (...)`. */
  hashIdentifierAll(kind: IdentifierKind, value: string): string[] {
    return this.requireHasher().hashAll(kind, value);
  }

  private requireHasher(): IdentifierHasher {
    if (!this.hasher) throw new IdentifierHashingUnavailableError();
    return this.hasher;
  }
}
