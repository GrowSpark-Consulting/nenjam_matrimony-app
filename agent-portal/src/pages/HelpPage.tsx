import { Link } from 'react-router-dom';
import { help, SUPPORT_CONTACT_PLACEHOLDER } from '../lib/helpContent';
import { usePortal } from '../state/PortalContext';

/**
 * Help & Support: the approved text, verbatim (see lib/helpContent.ts). The
 * contract has no help endpoint. The support contact is not confirmed yet, so
 * the placeholder is shown as-is — never an invented address or number.
 */
export function HelpPage() {
  const { stored } = usePortal();
  return (
    <section className="help">
      <h1>{help.title}</h1>
      <p>{help.welcome}</p>
      {help.sections.map((s) => (
        <div key={s.title}>
          <h2>{s.title}</h2>
          <p>{s.body}</p>
        </div>
      ))}
      <h2>{help.termsTitle}</h2>
      <ul>
        {help.terms.map((t) => (
          <li key={t}>{t}</li>
        ))}
      </ul>
      <p>{help.termsConsequence}</p>
      <h2>{help.needHelpTitle}</h2>
      <p>{help.contact.replace('{contact}', SUPPORT_CONTACT_PLACEHOLDER)}</p>
      <p>
        <strong>{help.otpWarning}</strong>
      </p>
      {!stored && <Link to="/sign-in">Back to sign in</Link>}
    </section>
  );
}
