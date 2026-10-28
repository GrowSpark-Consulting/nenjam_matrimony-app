/** In-memory fakes for the infrastructure ports. Tests only; not secure. */
import { createHmac, timingSafeEqual } from 'crypto';
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import type { AgentClock, AgentTokenSigner } from '../ports/agent-infra-ports';

export class FakeAgentClock implements AgentClock {
  private current: Date;

  constructor(start: Date) {
    this.current = new Date(start.getTime());
  }

  now(): Date {
    // A copy, so a caller mutating the result cannot move the clock.
    return new Date(this.current.getTime());
  }

  advance(ms: number): void {
    this.current = new Date(this.current.getTime() + ms);
  }

  set(at: Date): void {
    this.current = new Date(at.getTime());
  }
}

/**
 * `<base64url claims>.<base64url HMAC-SHA256>`. A stand-in for the real
 * signer, whose design is still a pending decision.
 */
export class FakeAgentTokenSigner implements AgentTokenSigner {
  constructor(private readonly key: string) {
    if (!key) throw new RangeError('key must be a non-empty string.');
  }

  private mac(payload: string): Buffer {
    return createHmac('sha256', this.key).update(payload).digest();
  }

  sign(claims: AgentAccessClaims): Promise<string> {
    const payload = Buffer.from(JSON.stringify(claims)).toString('base64url');
    return Promise.resolve(
      `${payload}.${this.mac(payload).toString('base64url')}`,
    );
  }

  verify(token: string): Promise<AgentAccessClaims | null> {
    if (typeof token !== 'string') return Promise.resolve(null);
    const parts = token.split('.');
    if (parts.length !== 2) return Promise.resolve(null);
    const [payload, signature] = parts;
    const given = Buffer.from(signature, 'base64url');
    const expected = this.mac(payload);
    if (given.length !== expected.length || !timingSafeEqual(given, expected)) {
      return Promise.resolve(null);
    }
    try {
      return Promise.resolve(
        JSON.parse(
          Buffer.from(payload, 'base64url').toString('utf8'),
        ) as AgentAccessClaims,
      );
    } catch {
      return Promise.resolve(null);
    }
  }
}
