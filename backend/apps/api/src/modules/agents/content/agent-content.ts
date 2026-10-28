/**
 * Display content for GET /agent/config: labels and share-message templates,
 * in English and Tamil.
 *
 * The share-message wording is APPROVED AND FINAL (Raja, 28 Oct 2026); it is
 * recorded in docs/agent-program/FRONTEND_HANDOFF_DHATRI.md section 6. Every
 * other Tamil label is still to be supplied and uses the single placeholder
 * below, which is the one place to replace when Raja sends them.
 */
import type {
  AgentContent,
  AgentContentPort,
} from '../ports/agent-content.port';

/** PENDING (Raja): Tamil wording for the labels that use this placeholder. */
export const AGENT_TAMIL_LABEL_PENDING = '<to be supplied>';

const pending = (en: string) => ({ en, ta: AGENT_TAMIL_LABEL_PENDING });

/** Each message ends with the link on its own line (dropped if no link). */
export const AGENT_SHARE_MESSAGE_EN = [
  "Hi! I'm {agent_name}. Join Nenjam, a trusted matrimony app, and use my referral code {code} when you sign up to get {discount_percent}% off your first plan.",
  '{link}',
].join('\n');

export const AGENT_SHARE_MESSAGE_TA = [
  'வணக்கம்! நான் {agent_name}. நம்பகமான திருமண வரன் தேடல் செயலியான "நெஞ்சம்" (Nenjam)-இல் இணையுங்கள். பதிவு செய்யும்போது என் பரிந்துரைக் குறியீடு {code} பயன்படுத்தினால், உங்கள் முதல் திட்டத்தில் {discount_percent}% தள்ளுபடி கிடைக்கும்.',
  '{link}',
].join('\n');

/**
 * English labels for Under review, Paused and Processing come from the API
 * contract; the others follow the same plain style.
 */
export const AGENT_CONTENT: AgentContent = {
  statusLabels: {
    PENDING_APPROVAL: pending('Under review'),
    ACTIVE: pending('Active'),
    REJECTED: pending('Rejected'),
    SUSPENDED: pending('Paused'),
    TERMINATED: pending('Terminated'),
  },
  stageLabels: {
    REGISTERED: pending('Registered'),
    PROFILE_COMPLETE: pending('Profile complete'),
    PURCHASED: pending('Purchased'),
  },
  commissionStatusLabels: {
    ON_HOLD: pending('On hold'),
    APPROVED: pending('Approved'),
    PAID: pending('Paid'),
    CANCELLED: pending('Cancelled'),
  },
  payoutStatusLabels: {
    CREATED: pending('Processing'),
    PAID: pending('Paid'),
    CANCELLED: pending('Cancelled'),
  },
  shareMessageTemplates: [
    {
      id: 'default',
      text: { en: AGENT_SHARE_MESSAGE_EN, ta: AGENT_SHARE_MESSAGE_TA },
    },
  ],
};

/** The content held in this file, served through the content port. */
export class StaticAgentContent implements AgentContentPort {
  getContent(): Promise<AgentContent> {
    // A copy, so a caller cannot edit the shared constant.
    return Promise.resolve(structuredClone(AGENT_CONTENT));
  }
}
