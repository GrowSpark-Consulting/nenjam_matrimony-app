import { usePortal } from '../state/PortalContext';
import { ErrorText } from './ErrorText';
import { Loading } from './Loading';

/**
 * Shown to a signed-in agent whose profile (`GET /agent/me`) could not be
 * loaded. The session is kept: this is "try again", not "sign in again" (a
 * 401 is the only thing that ends the session, and HttpClient handles it).
 */
export function AgentLoadError() {
  const { agentError, loading, retryAgent, signOut } = usePortal();
  return (
    <div className="app">
      <main className="main narrow">
        <h1>We couldn't load your account</h1>
        {loading ? <Loading /> : <ErrorText error={agentError} onRetry={retryAgent} />}
        <p>
          <button type="button" className="link" onClick={() => void signOut()}>
            Sign out
          </button>
        </p>
      </main>
    </div>
  );
}
