/**
 * Port for encrypting small secrets before they are stored (the full PAN,
 * payout details, an applicant's phone).
 *
 * Every value is sealed for one PURPOSE (one of `AGENT_SEAL_PURPOSES`) and
 * opens only under that same purpose: a PAN copied into the payout-details
 * column fails to open instead of decrypting as the wrong thing.
 *
 * Contract: `open(p, seal(p, x))` returns `x`; two seals of the same text
 * differ; the sealed text never contains the plaintext; `open` rejects text
 * that was altered, sealed with another key or sealed for another purpose.
 * No error message or log line may contain the plaintext or the key.
 */
export const AGENT_SEAL_PURPOSES = {
  pan: 'agent.pan',
  payoutDetails: 'agent.payout_details',
  applicantPhone: 'agent.applicant_phone',
} as const;

export type AgentSealPurpose =
  (typeof AGENT_SEAL_PURPOSES)[keyof typeof AGENT_SEAL_PURPOSES];

export interface AgentSecretSealer {
  seal(purpose: AgentSealPurpose, plaintext: string): string;
  open(purpose: AgentSealPurpose, sealed: string): string;
}
