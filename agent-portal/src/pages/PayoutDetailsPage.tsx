import { useState, type FormEvent } from 'react';
import type { PayoutDetailsInput, PayoutDetailsSummary } from '../api/types';
import { ErrorText } from '../components/ErrorText';
import {
  ACCOUNT_PATTERN,
  IFSC_PATTERN,
  normalizeAccountNumber,
  normalizeIfsc,
  normalizeUpi,
  UPI_PATTERN,
} from '../lib/normalize';
import { usePortal } from '../state/PortalContext';

/** Builds the PATCH body: exactly one of `upi` or `bank`, cleaned as the contract asks. */
export function buildPayoutDetails(
  method: 'UPI' | 'BANK',
  fields: { vpa: string; holder: string; account: string; ifsc: string },
): PayoutDetailsInput | null {
  if (method === 'UPI') {
    const vpa = normalizeUpi(fields.vpa);
    return UPI_PATTERN.test(vpa) ? { upi: { vpa } } : null;
  }
  const accountHolderName = fields.holder.trim();
  const accountNumber = normalizeAccountNumber(fields.account);
  const ifsc = normalizeIfsc(fields.ifsc);
  if (!accountHolderName || accountHolderName.length > 100) return null;
  if (!ACCOUNT_PATTERN.test(accountNumber) || !IFSC_PATTERN.test(ifsc)) return null;
  return { bank: { accountHolderName, accountNumber, ifsc } };
}

/**
 * `PATCH /agent/me/payout-details` (ACTIVE only). Only says WHERE an
 * admin-created payout goes — agents cannot create payouts. The response is
 * masked; the full number or UPI id is never shown back.
 */
export function PayoutDetailsPage() {
  const { api, reloadAgent } = usePortal();
  const [method, setMethod] = useState<'UPI' | 'BANK'>('UPI');
  const [vpa, setVpa] = useState('');
  const [holder, setHolder] = useState('');
  const [account, setAccount] = useState('');
  const [ifsc, setIfsc] = useState('');
  const [saved, setSaved] = useState<PayoutDetailsSummary | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  const body = buildPayoutDetails(method, { vpa, holder, account, ifsc });

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!body || busy) return;
    setBusy(true);
    setError(null);
    try {
      setSaved(await api.updatePayoutDetails(body));
      reloadAgent();
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  }

  return (
    <section>
      <h1>Payout details</h1>
      <p className="hint">Check these carefully before saving.</p>
      <form onSubmit={submit}>
        <fieldset>
          <legend>Paid to</legend>
          <label>
            <input type="radio" checked={method === 'UPI'} onChange={() => setMethod('UPI')} /> UPI
          </label>
          <label>
            <input type="radio" checked={method === 'BANK'} onChange={() => setMethod('BANK')} />{' '}
            Bank account
          </label>
        </fieldset>
        {method === 'UPI' ? (
          <>
            <label htmlFor="vpa">UPI ID</label>
            <input id="vpa" value={vpa} placeholder="name@bank" onChange={(e) => setVpa(e.target.value)} />
          </>
        ) : (
          <>
            <label htmlFor="holder">Account holder name</label>
            <input id="holder" value={holder} maxLength={100} onChange={(e) => setHolder(e.target.value)} />
            <label htmlFor="account">Account number</label>
            <input
              id="account"
              inputMode="numeric"
              value={account}
              onChange={(e) => setAccount(e.target.value)}
            />
            <label htmlFor="ifsc">IFSC</label>
            <input
              id="ifsc"
              value={ifsc}
              autoCapitalize="characters"
              placeholder="HDFC0001234"
              onChange={(e) => setIfsc(e.target.value)}
            />
          </>
        )}
        <button type="submit" disabled={!body || busy}>
          Save
        </button>
      </form>
      <ErrorText error={error} />
      {saved && (
        <p role="status">
          Saved: {saved.method === 'UPI' ? 'UPI' : 'Bank'} {saved.display}
        </p>
      )}
    </section>
  );
}
