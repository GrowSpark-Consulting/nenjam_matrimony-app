/**
 * Builds the agent's profile as clients see it (the contract's AgentProfile).
 *
 * Output only: the phone is masked, the PAN is last four only, and nothing
 * sealed or hashed is ever included. Shared by sign-in, application and `me`
 * so the three can never disagree about what a profile contains.
 */
import type {
  AgentContentPort,
  AgentLocalizedText,
} from '../ports/agent-content.port';
import type {
  AgentRecord,
  ReferralCodeRepository,
} from '../ports/agent-data-ports';
import type { AgentTx } from '../ports/agent-unit-of-work.port';
import { IST_OFFSET_MS, maskPhone } from '../referral/agent-referral-view';

export interface AgentProfile {
  id: string;
  name: string;
  phoneMasked: string;
  city: string;
  state: string;
  status: string;
  statusLabel: AgentLocalizedText;
  rejectionReason: string | null;
  /** IST calendar date, "YYYY-MM-DD". */
  approvedAt: string | null;
  panLast4: string | null;
  payoutDetailsSet: boolean;
  /** The primary code; null until the agent has one (approval). */
  primaryCode: string | null;
}

export class AgentProfileBuilder {
  constructor(
    private readonly content: AgentContentPort,
    private readonly codes: ReferralCodeRepository,
  ) {}

  async build(agent: AgentRecord, tx?: AgentTx): Promise<AgentProfile> {
    const [content, codes] = await Promise.all([
      this.content.getContent(),
      this.codes.listByAgent(agent.id, tx),
    ]);
    const label = (
      content.statusLabels as Record<string, AgentLocalizedText | undefined>
    )[agent.status];
    if (!label) {
      throw new RangeError(`No label is defined for status ${agent.status}.`);
    }
    return {
      id: agent.id,
      name: agent.name,
      phoneMasked: maskPhone(agent.phoneE164),
      city: agent.city,
      state: agent.state,
      status: agent.status,
      statusLabel: label,
      // Only a REJECTED agent has a reason to show.
      rejectionReason:
        agent.status === 'REJECTED' ? agent.rejectionReason : null,
      approvedAt:
        agent.approvedAt === null
          ? null
          : new Date(agent.approvedAt.getTime() + IST_OFFSET_MS)
              .toISOString()
              .slice(0, 10),
      panLast4: agent.panLast4,
      payoutDetailsSet: agent.payoutDetailsSet,
      primaryCode:
        codes.find((code) => code.isPrimary && code.isActive)?.code ?? null,
    };
  }
}
