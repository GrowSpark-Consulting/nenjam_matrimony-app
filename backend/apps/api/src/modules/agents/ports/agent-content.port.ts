/**
 * Port for the display content served by GET /agent/config: labels and
 * share-message templates, in English and Tamil.
 */
import type { AgentStatus } from '../agent/agent-status';
import type {
  PublicCommissionStatus,
  ReferralStage,
} from '../referral/agent-referral-view';

export interface AgentLocalizedText {
  en: string;
  ta: string;
}

export type AgentPayoutStatus = 'CREATED' | 'PAID' | 'CANCELLED';

export interface AgentShareMessageTemplate {
  id: string;
  /** Contains placeholders such as {agent_name}, {code}, {link}. */
  text: AgentLocalizedText;
}

export interface AgentContent {
  statusLabels: Record<AgentStatus, AgentLocalizedText>;
  stageLabels: Record<ReferralStage, AgentLocalizedText>;
  commissionStatusLabels: Record<PublicCommissionStatus, AgentLocalizedText>;
  payoutStatusLabels: Record<AgentPayoutStatus, AgentLocalizedText>;
  shareMessageTemplates: readonly AgentShareMessageTemplate[];
}

export interface AgentContentPort {
  getContent(): Promise<AgentContent>;
}
