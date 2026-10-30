import { QRCodeSVG } from 'qrcode.react';
import { useCallback, useState } from 'react';
import type { ReferralLink, ShareMessage } from '../api/types';
import { isRouteNotDeployed } from '../api/errors';
import { ComingSoon } from '../components/ComingSoon';
import { ErrorText } from '../components/ErrorText';
import { Loading } from '../components/Loading';
import { useAsync } from '../components/useAsync';
import { formatPaise } from '../lib/money';
import { usePortal } from '../state/PortalContext';

/** WhatsApp share without any API: `wa.me` with the message as `text`. */
export function whatsAppUrl(message: string): string {
  return `https://wa.me/?text=${encodeURIComponent(message)}`;
}

/**
 * Home: the agent's codes (`GET /agent/referral-links`) and a balance
 * summary (`GET /agent/balance`).
 *
 * Share messages come ready-made, per code, from the backend; they are shown
 * and shared exactly as received — never rebuilt here, and never generated
 * from the `/agent/config` templates. `link`/`qrPayload` are null until the
 * public web address is decided, and are then simply not shown.
 */
export function HomePage() {
  const { api } = usePortal();
  const links = useAsync(useCallback(() => api.getReferralLinks(), [api]));
  const balance = useAsync(useCallback(() => api.getBalance(), [api]));

  return (
    <section>
      <h1>Your referral code</h1>
      {links.loading && <Loading />}
      <ErrorText error={links.error} onRetry={links.reload} />
      {links.data?.map((l) => <CodeCard key={l.codeId} link={l} />)}

      <h2>Balance</h2>
      {balance.loading && <Loading />}
      {isRouteNotDeployed(balance.error) ? (
        <ComingSoon what="Your balance" />
      ) : (
        <ErrorText error={balance.error} onRetry={balance.reload} />
      )}
      {balance.data && (
        <dl className="facts">
          <dt>On hold</dt>
          <dd>{formatPaise(balance.data.onHoldPaise)}</dd>
          <dt>Available</dt>
          <dd>{formatPaise(balance.data.availablePaise)}</dd>
          <dt>Paid</dt>
          <dd>{formatPaise(balance.data.paidPaise)}</dd>
        </dl>
      )}
    </section>
  );
}

function CodeCard({ link }: { link: ReferralLink }) {
  const [copied, setCopied] = useState<string | null>(null);

  async function copy(id: string, text: string) {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(id);
    } catch {
      setCopied(null);
    }
  }

  return (
    <div className="card">
      <p className="code" aria-label="Referral code">
        {link.code}
      </p>
      <button onClick={() => void copy('code', link.code)}>
        {copied === 'code' ? 'Copied' : 'Copy code'}
      </button>
      {!link.shareable && (
        <p className="hint">Sharing is turned off while your account is paused.</p>
      )}
      {link.link && <p className="hint">{link.link}</p>}
      {link.qrPayload && (
        <div className="qr">
          <QRCodeSVG value={link.qrPayload} size={160} />
        </div>
      )}
      {link.shareMessages.map((m) => (
        <ShareBlock
          key={m.id}
          message={m}
          shareable={link.shareable}
          copied={copied}
          onCopy={copy}
        />
      ))}
    </div>
  );
}

function ShareBlock({
  message,
  shareable,
  copied,
  onCopy,
}: {
  message: ShareMessage;
  shareable: boolean;
  copied: string | null;
  onCopy: (id: string, text: string) => Promise<void>;
}) {
  const variants = [
    { lang: 'English', text: message.text.en },
    { lang: 'Tamil', text: message.text.ta },
  ].filter((v) => v.text && v.text.trim() && v.text.trim() !== '<to be supplied>');

  return (
    <>
      {variants.map((v) => {
        const id = `${message.id}-${v.lang}`;
        return (
          <div key={id} className="share">
            <h3>Message in {v.lang}</h3>
            <p className="message">{v.text}</p>
            {shareable ? (
              <a className="button" href={whatsAppUrl(v.text)} target="_blank" rel="noreferrer">
                Share on WhatsApp
              </a>
            ) : (
              <button disabled>Share on WhatsApp</button>
            )}
            <button disabled={!shareable} onClick={() => void onCopy(id, v.text)}>
              {copied === id ? 'Copied' : 'Copy message'}
            </button>
          </div>
        );
      })}
    </>
  );
}
