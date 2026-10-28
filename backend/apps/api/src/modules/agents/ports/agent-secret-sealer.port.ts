/**
 * Port for encrypting small secrets before they are stored (the full PAN,
 * payout details, an applicant's phone).
 *
 * Contract: `open(seal(x))` returns `x`; two seals of the same text differ;
 * the sealed text never contains the plaintext; `open` rejects text that was
 * altered or sealed with another key. No error message or log line may
 * contain the plaintext or the key.
 */
export interface AgentSecretSealer {
  seal(plaintext: string): string;
  open(sealed: string): string;
}
