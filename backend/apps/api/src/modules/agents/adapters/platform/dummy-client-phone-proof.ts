/**
 * `ClientPhoneProofPort` while there is no SMS: the one-time code of Shaaz's
 * `OtpService` (purpose AGENT_CLIENT_CONSENT, through our `AgentOtpPort`),
 * which today can only be the test (dummy) code.
 *
 * WHO A CODE CAN REACH. Only a phone that is EXPLICITLY on the approved test
 * list (AGENT_OTP_DUMMY_PHONES), with the dummy code switched on and set
 * (AGENT_OTP_DUMMY_ENABLED, AGENT_OTP_DUMMY_CODE), in EVERY environment. The
 * OTP service itself also covers any phone outside production when that list
 * is empty; that mode is deliberately ignored here: with a code anyone
 * knows, "any phone" would let an agent (or anyone) confirm for a stranger.
 * A phone that is not reachable is refused before the OTP service is called.
 *
 * THE NEWEST CODE PER PHONE. A code lives minutes; an invitation lives days.
 * So the client sends her phone and the code, never a challenge id: `send`
 * remembers the newest challenge per phone hash (`AgentClientConsentCodeStore`)
 * and `verify` checks that one. A code sent by an agent's submit and one the
 * client asked for both work; the newer replaces the older.
 *
 * REAL SMS LATER: a `FIREBASE_ID_TOKEN` proof (Firebase phone sign-in,
 * verified server side) is a new adapter for this port; this one answers
 * UNSUPPORTED for it.
 */
import { AgentServiceError } from '../../errors/agent-service-error';
import type {
  AgentClientConsentCodeStore,
  ClientPhoneProof,
  ClientPhoneProofPort,
  ClientPhoneProofResult,
} from '../../ports/agent-client-ports';
import type {
  AgentIdentifierHasher,
  AgentOtpPort,
} from '../../ports/agent-platform-ports';

/** The deployment's dummy-code settings (`AppConfigService.agentOtp`). Never logged. */
export interface ClientDummyCodeConfig {
  dummyEnabled: boolean;
  dummyPhones: readonly string[];
  dummyCode?: string;
}

export interface DummyClientPhoneProofDeps {
  otp: AgentOtpPort;
  codes: AgentClientConsentCodeStore;
  hasher: AgentIdentifierHasher;
  config: ClientDummyCodeConfig;
}

export class DummyClientPhoneProof implements ClientPhoneProofPort {
  constructor(private readonly deps: DummyClientPhoneProofDeps) {}

  canReach(phoneE164: string): boolean {
    const { dummyEnabled, dummyPhones, dummyCode } = this.deps.config;
    return (
      dummyEnabled === true &&
      typeof dummyCode === 'string' &&
      dummyCode.length > 0 &&
      dummyPhones.includes(phoneE164)
    );
  }

  async send(phoneE164: string): Promise<{ expiresAt: Date }> {
    if (!this.canReach(phoneE164)) {
      throw new AgentServiceError('OTP_DELIVERY_UNAVAILABLE');
    }
    // A rate limit (AgentOtpRateLimitError) passes through to the caller.
    const challenge = await this.deps.otp.send(
      'AGENT_CLIENT_CONSENT',
      phoneE164,
    );
    await this.deps.codes.save({
      phoneHash: this.deps.hasher.hash('PHONE', phoneE164),
      challengeId: challenge.challengeId,
      expiresAt: challenge.expiresAt,
    });
    return { expiresAt: challenge.expiresAt };
  }

  async verify(proof: ClientPhoneProof): Promise<ClientPhoneProofResult> {
    if (proof.kind !== 'CODE') return { ok: false, reason: 'UNSUPPORTED' };
    // Taken off the list since the code was sent: it no longer verifies.
    if (!this.canReach(proof.phoneE164)) {
      return { ok: false, reason: 'NOT_FOUND' };
    }
    const hashes = this.deps.hasher.hashAll('PHONE', proof.phoneE164);
    const pointer = await this.deps.codes.find(hashes);
    if (pointer === null) return { ok: false, reason: 'NOT_FOUND' };
    const result = await this.deps.otp.verify(
      'AGENT_CLIENT_CONSENT',
      pointer.challengeId,
      proof.code,
    );
    if (!result.ok) return result;
    // The challenge was issued for this phone; anything else is a stray pointer.
    if (result.phoneE164 !== proof.phoneE164) {
      return { ok: false, reason: 'NOT_FOUND' };
    }
    await this.deps.codes.delete(hashes);
    return { ok: true, phoneE164: result.phoneE164 };
  }
}
