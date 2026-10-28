import { buildAgentAccessClaims } from '../auth/agent-access-claims';
import type { AgentContent } from '../ports/agent-content.port';
import { FakeAgentContent } from './fake-agent-content';
import { FakeAgentClock, FakeAgentTokenSigner } from './fake-agent-infra';

const START = new Date('2026-10-28T10:00:00.000Z');

describe('FakeAgentClock (AgentClock contract)', () => {
  it('returns the start time, then moves only when told to', () => {
    const clock = new FakeAgentClock(START);
    expect(clock.now()).toEqual(START);
    clock.advance(60_000);
    expect(clock.now().toISOString()).toBe('2026-10-28T10:01:00.000Z');
    clock.set(START);
    expect(clock.now()).toEqual(START);
  });

  it('cannot be moved by mutating a returned date or the start date', () => {
    const start = new Date(START.getTime());
    const clock = new FakeAgentClock(start);
    start.setFullYear(2000);
    clock.now().setFullYear(2000);
    expect(clock.now()).toEqual(START);
  });
});

describe('FakeAgentTokenSigner (AgentTokenSigner contract)', () => {
  const claims = buildAgentAccessClaims({
    agentId: 'agent-1',
    phoneHash: 'hash',
    scope: 'AGENT',
    now: START,
    ttlSeconds: 900,
    issuer: 'nenjam',
    audience: 'agent',
  });

  it('round-trips claims', async () => {
    const signer = new FakeAgentTokenSigner('k1');
    await expect(signer.verify(await signer.sign(claims))).resolves.toEqual(
      claims,
    );
  });

  it('rejects a token signed with another key', async () => {
    const token = await new FakeAgentTokenSigner('k1').sign(claims);
    await expect(
      new FakeAgentTokenSigner('k2').verify(token),
    ).resolves.toBeNull();
  });

  it('rejects a tampered payload and garbage', async () => {
    const signer = new FakeAgentTokenSigner('k1');
    const [, signature] = (await signer.sign(claims)).split('.');
    const forged = Buffer.from(
      JSON.stringify({ ...claims, sub: 'agent-2' }),
    ).toString('base64url');
    await expect(signer.verify(`${forged}.${signature}`)).resolves.toBeNull();
    for (const bad of ['', 'abc', 'a.b.c', '.']) {
      await expect(signer.verify(bad)).resolves.toBeNull();
    }
  });

  it('does not judge expiry (that is validateAgentAccessClaims)', async () => {
    const signer = new FakeAgentTokenSigner('k1');
    const expired = { ...claims, exp: claims.iat - 1 };
    await expect(signer.verify(await signer.sign(expired))).resolves.toEqual(
      expired,
    );
  });

  it('refuses an empty key', () => {
    expect(() => new FakeAgentTokenSigner('')).toThrow(RangeError);
  });
});

describe('FakeAgentContent (AgentContentPort contract)', () => {
  const content = {
    shareMessageTemplates: [{ id: 'default', text: { en: 'a', ta: 'b' } }],
  } as unknown as AgentContent;

  it('returns the content, and editing the result does not change the store', async () => {
    const port = new FakeAgentContent(content);
    const first = await port.getContent();
    first.shareMessageTemplates[0].text.en = 'changed';
    const second = await port.getContent();
    expect(second.shareMessageTemplates[0].text.en).toBe('a');
  });
});
