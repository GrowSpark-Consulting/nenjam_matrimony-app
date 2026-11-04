/**
 * In-memory `AgentClientMemberProfilePort`: which members have a profile
 * row, and the calls made. Tests only.
 */
import type { AgentClientMemberProfilePort } from '../ports/agent-client-ports';

export class FakeAgentMemberProfiles implements AgentClientMemberProfilePort {
  private readonly made = new Set<string>();
  /** Calls made, for assertions. */
  readonly calls = { exists: 0, createFromDraft: [] as string[] };
  /** Make the next `createFromDraft` calls fail (a database error...). */
  failCreate: Error | null = null;
  /** Make `exists` fail. */
  failExists: Error | null = null;
  /** `createFromDraft` returns without making the row (a draft that is not enough). */
  makesNothing = false;
  /** Called at the start of every `createFromDraft`, for assertions on the moment. */
  onCreate: ((memberId: string) => void) | null = null;

  has(memberId: string): boolean {
    return this.made.has(memberId);
  }

  exists(memberId: string): Promise<boolean> {
    this.calls.exists += 1;
    if (this.failExists) return Promise.reject(this.failExists);
    return Promise.resolve(this.made.has(memberId));
  }

  createFromDraft(memberId: string): Promise<void> {
    this.calls.createFromDraft.push(memberId);
    this.onCreate?.(memberId);
    if (this.failCreate) return Promise.reject(this.failCreate);
    if (!this.makesNothing) this.made.add(memberId);
    return Promise.resolve();
  }
}
