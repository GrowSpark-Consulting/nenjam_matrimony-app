import { useState, type FormEvent } from 'react';
import type { PayoutDetailsInput, PayoutDetailsSummary } from '../api/types';
import { isRouteNotDeployed } from '../api/errors';
import { ErrorText } from '../components/ErrorText';
import { ComingSoonState, FormField, PageHeader, StatusBadge } from '../components/ui';
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
 * masked; the full number or UPI id is never shown back. Fields are cleared
 * after a successful save so what's on screen is never mistaken for what's
 * stored, and nothing is reported as saved unless the request succeeded.
 */
export function PayoutDetailsPage() {
  const { api, agent, reloadAgent } = usePortal();
  const [method, setMethod] = useState<'UPI' | 'BANK'>('UPI');
  const [vpa, setVpa] = useState('');
  const [holder, setHolder] = useState('');
  const [account, setAccount] = useState('');
  const [ifsc, setIfsc] = useState('');
  const [saved, setSaved] = useState<PayoutDetailsSummary | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  const body = buildPayoutDetails(method, { vpa, holder, account, ifsc });
  const dirty = !!(vpa || holder || account || ifsc);

  const vpaError = vpa && !body ? 'Enter a UPI ID like name@bank.' : null;
  const holderError =
    holder && holder.trim().length > 100 ? 'Use 100 characters or fewer.' : null;
  const accountError =
    account && !ACCOUNT_PATTERN.test(normalizeAccountNumber(account))
      ? 'Enter 9 to 18 digits, with no letters.'
      : null;
  const ifscError =
    ifsc && !IFSC_PATTERN.test(normalizeIfsc(ifsc)) ? 'An IFSC looks like HDFC0001234.' : null;

  function cancel() {
    setVpa('');
    setHolder('');
    setAccount('');
    setIfsc('');
    setError(null);
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!body || busy) return;
    setBusy(true);
    setError(null);
    setSaved(null);
    try {
      setSaved(await api.updatePayoutDetails(body));
      cancel();
      reloadAgent();
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  }

  if (isRouteNotDeployed(error)) {
    return (
      <>
        <PageHeader title="Payout details" />
        <ComingSoonState title="Payout details coming soon" icon="bank">
          Saving payout details isn't switched on yet. Nothing you entered was saved. Please come
          back later.
        </ComingSoonState>
      </>
    );
  }

  return (
    <>
      <PageHeader
        title="Payout details"
        description="This is where the Nenjam team sends your payouts. Check these carefully before saving."
        action={
          (saved || agent?.payoutDetailsSet) && (
            <StatusBadge tone="success">Details on file</StatusBadge>
          )
        }
      />
      {saved && (
        <div className="notice success-notice" role="status">
          Saved: {saved.method === 'UPI' ? 'UPI' : 'Bank'} {saved.display}
        </div>
      )}
      <form className="card form-card" onSubmit={submit}>
        <h2>{saved || agent?.payoutDetailsSet ? 'Replace your details' : 'Add your details'}</h2>
        <p className="hint">
          {dirty
            ? 'You have changes that are not saved yet.'
            : 'Details you enter here are only stored when you press Save.'}
        </p>
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
          <FormField id="vpa" label="UPI ID" error={vpaError}>
            {(p) => (
              <input {...p} value={vpa} placeholder="name@bank" onChange={(e) => setVpa(e.target.value)} />
            )}
          </FormField>
        ) : (
          <>
            <FormField id="holder" label="Account holder name" error={holderError}>
              {(p) => (
                <input {...p} value={holder} maxLength={100} onChange={(e) => setHolder(e.target.value)} />
              )}
            </FormField>
            <FormField id="account" label="Account number" error={accountError}>
              {(p) => (
                <input
                  {...p}
                  inputMode="numeric"
                  value={account}
                  onChange={(e) => setAccount(e.target.value)}
                />
              )}
            </FormField>
            <FormField id="ifsc" label="IFSC" error={ifscError}>
              {(p) => (
                <input
                  {...p}
                  value={ifsc}
                  autoCapitalize="characters"
                  placeholder="HDFC0001234"
                  onChange={(e) => setIfsc(e.target.value)}
                />
              )}
            </FormField>
          </>
        )}
        <div className="actions">
          <button type="submit" disabled={!body || busy}>
            {busy ? 'Saving…' : 'Save'}
          </button>
          <button type="button" className="secondary" disabled={!dirty || busy} onClick={cancel}>
            Cancel
          </button>
        </div>
      </form>
      <ErrorText error={error} />
    </>
  );
}
