import { QRCodeSVG } from 'qrcode.react';
import { useState } from 'react';
import type { ReferralLink, ShareMessage } from '../api/types';
import { Icon } from './ui';

/** WhatsApp share without any API: `wa.me` with the message as `text`. */
function whatsAppUrl(message: string): string {
  return `https://wa.me/?text=${encodeURIComponent(message)}`;
}

type CopyResult = { id: string; ok: boolean } | null;

/**
 * One referral code with its ready-made share messages. Messages come from
 * the backend per code and are shown and shared exactly as received. `link`
 * and `qrPayload` are null until the public web address is decided, and are
 * then simply not shown.
 */
export function ReferralCodeCard({ link }: { link: ReferralLink }) {
  const [result, setResult] = useState<CopyResult>(null);

  async function copy(id: string, text: string) {
    try {
      await navigator.clipboard.writeText(text);
      setResult({ id, ok: true });
    } catch {
      setResult({ id, ok: false });
    }
  }

  const codeCopied = result?.id === 'code' && result.ok;

  return (
    <div className="card code-card">
      <div className="code-row">
        <p className="code" aria-label="Referral code">
          {link.code}
        </p>
        <button type="button" onClick={() => void copy('code', link.code)}>
          <Icon name={codeCopied ? 'check' : 'copy'} size={18} />
          {codeCopied ? 'Copied' : 'Copy code'}
        </button>
      </div>
      <p className="copy-feedback" role="status" aria-live="polite">
        {codeCopied && 'Copied to your clipboard.'}
        {result?.id === 'code' && !result.ok && (
          <span className="error">Couldn't copy. Select the code and copy it yourself.</span>
        )}
      </p>
      {!link.shareable && (
        <p className="notice">Sharing is turned off while your account is paused.</p>
      )}
      {link.link && <p className="hint">{link.link}</p>}
      {link.qrPayload && (
        <div className="qr">
          <QRCodeSVG value={link.qrPayload} size={160} />
        </div>
      )}
      <div className="share-list">
        {link.shareMessages.map((m) => (
          <ShareBlock key={m.id} message={m} shareable={link.shareable} result={result} onCopy={copy} />
        ))}
      </div>
    </div>
  );
}

function ShareBlock({
  message,
  shareable,
  result,
  onCopy,
}: {
  message: ShareMessage;
  shareable: boolean;
  result: CopyResult;
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
        const copied = result?.id === id && result.ok;
        return (
          <div key={id} className="share">
            <h3>Message in {v.lang}</h3>
            <p className="message">{v.text}</p>
            <div className="actions">
              {shareable ? (
                <a className="button" href={whatsAppUrl(v.text)} target="_blank" rel="noreferrer">
                  <Icon name="whatsapp" size={18} />
                  Share on WhatsApp
                </a>
              ) : (
                <button type="button" disabled>
                  <Icon name="whatsapp" size={18} />
                  Share on WhatsApp
                </button>
              )}
              <button
                type="button"
                className="secondary"
                disabled={!shareable}
                onClick={() => void onCopy(id, v.text)}
              >
                <Icon name={copied ? 'check' : 'copy'} size={18} />
                {copied ? 'Copied' : 'Copy message'}
              </button>
            </div>
            {result?.id === id && !result.ok && (
              <p className="error field-error" role="alert">
                Couldn't copy. Select the message and copy it yourself.
              </p>
            )}
          </div>
        );
      })}
    </>
  );
}
