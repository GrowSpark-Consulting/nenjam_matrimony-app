/** In-memory content port. Tests only. */
import type {
  AgentContent,
  AgentContentPort,
} from '../ports/agent-content.port';

export class FakeAgentContent implements AgentContentPort {
  constructor(private content: AgentContent) {}

  set(content: AgentContent): void {
    this.content = content;
  }

  getContent(): Promise<AgentContent> {
    // A copy, so a caller cannot edit the stored content.
    return Promise.resolve(structuredClone(this.content));
  }
}
