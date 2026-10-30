/** A real sealer with a fixed test key. Tests only. */
import { AgentPiiSealer } from '../crypto/agent-pii-sealer';

// Not a secret: a pattern that exists only in test code.
const TEST_KEY = Buffer.alloc(32, 7);

export class FakeAgentSecretSealer extends AgentPiiSealer {
  constructor() {
    super(TEST_KEY);
  }
}
