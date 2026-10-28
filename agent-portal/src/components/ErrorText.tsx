import { useEffect } from 'react';
import { ApiError } from '../api/errors';
import { usePortal } from '../state/PortalContext';

/**
 * The text to show for a failed call. 4xx answers use the server's own
 * `message` (the contract's rule; React renders it as text, never HTML).
 * Server errors and network failures get a fixed sentence instead, so no raw
 * server output or stack trace can reach the screen.
 */
// eslint-disable-next-line react-refresh/only-export-components
export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.isNetworkError) {
      return "Couldn't reach Nenjam. Check your connection and try again.";
    }
    if (error.isServerError) {
      return 'The service is having trouble right now. Please try again shortly.';
    }
    if (error.isRateLimited) {
      return error.retryAfterSeconds
        ? `Too many tries, please wait ${error.retryAfterSeconds} seconds and try again.`
        : 'Too many tries, please wait and try again.';
    }
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}

export function ErrorText({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const { reloadAgent } = usePortal();
  // The agent's status changed under us (e.g. paused by an admin): re-read
  // it so the screens and navigation follow the new status.
  const notActive = error instanceof ApiError && error.code === 'AGENT_NOT_ACTIVE';
  useEffect(() => {
    if (notActive) reloadAgent();
  }, [notActive, reloadAgent]);

  if (!error) return null;
  return (
    <div className="error-box" role="alert">
      <p className="error">{errorMessage(error)}</p>
      {onRetry && (
        <button type="button" className="secondary" onClick={onRetry}>
          Try again
        </button>
      )}
    </div>
  );
}
