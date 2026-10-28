/** A real AES-256-GCM sealer with a fixed test key. Tests only. */
import { AesGcmSecretSealer } from '../crypto/aes-gcm-secret-sealer';

// Not a secret: a pattern that exists only in test code.
const TEST_KEY = Buffer.alloc(32, 7);

export class FakeAgentSecretSealer extends AesGcmSecretSealer {
  constructor() {
    super(TEST_KEY);
  }
}
