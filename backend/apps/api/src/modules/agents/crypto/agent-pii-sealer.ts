/**
 * `AgentSecretSealer` over Shaaz's `SecretSealer` (`@app/common`): one
 * instance per purpose, all with the same key (`AGENT_PII_ENCRYPTION_KEY`).
 * The purpose is bound to every value as GCM additional data, so a value
 * sealed for one purpose does not open under another. This file reads no
 * environment and holds no key of its own.
 */
import { SecretSealer } from '@app/common';
import {
  AGENT_SEAL_PURPOSES,
  type AgentSealPurpose,
  type AgentSecretSealer,
} from '../ports/agent-secret-sealer.port';

export class AgentPiiSealer implements AgentSecretSealer {
  private readonly byPurpose: ReadonlyMap<string, SecretSealer>;

  constructor(key: Buffer) {
    this.byPurpose = new Map(
      Object.values(AGENT_SEAL_PURPOSES).map((purpose) => [
        purpose,
        new SecretSealer(key, purpose),
      ]),
    );
  }

  seal(purpose: AgentSealPurpose, plaintext: string): string {
    return this.sealerFor(purpose).seal(plaintext);
  }

  open(purpose: AgentSealPurpose, sealed: string): string {
    return this.sealerFor(purpose).open(sealed);
  }

  private sealerFor(purpose: string): SecretSealer {
    const sealer = this.byPurpose.get(purpose);
    if (!sealer) throw new RangeError('Unknown sealing purpose.');
    return sealer;
  }
}
