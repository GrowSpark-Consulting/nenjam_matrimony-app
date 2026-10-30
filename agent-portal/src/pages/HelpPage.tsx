import { Link } from 'react-router-dom';
import { PageHeader } from '../components/ui';
import { help, SUPPORT_CONTACT_PLACEHOLDER } from '../lib/helpContent';
import { usePortal } from '../state/PortalContext';

/**
 * Help & Support: the approved text, verbatim (see lib/helpContent.ts). The
 * contract has no help endpoint. The support contact is not confirmed yet, so
 * the placeholder is shown as-is — never an invented address or number.
 */
export function HelpPage() {
  const { stored } = usePortal();
  const body = (
    <>
      <PageHeader title={help.title} description={help.welcome} />
      <div className="help">
        {help.sections.map((s) => (
          <section key={s.title} className="card">
            <h2>{s.title}</h2>
            <p>{s.body}</p>
          </section>
        ))}
        <section className="card">
          <h2>{help.termsTitle}</h2>
          <ul>
            {help.terms.map((t) => (
              <li key={t}>{t}</li>
            ))}
          </ul>
          <p>{help.termsConsequence}</p>
        </section>
        <section className="card">
          <h2>{help.needHelpTitle}</h2>
          <p>{help.contact.replace('{contact}', SUPPORT_CONTACT_PLACEHOLDER)}</p>
          <p className="notice">
            <strong>{help.otpWarning}</strong>
          </p>
        </section>
      </div>
      {!stored && <Link to="/sign-in">Back to sign in</Link>}
    </>
  );
  // Signed in, the shell already provides <main>; signed out it stands alone.
  return stored ? body : <main className="main help-public">{body}</main>;
}
