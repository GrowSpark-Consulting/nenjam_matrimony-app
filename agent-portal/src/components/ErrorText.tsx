import { useEffect } from 'react';
import { ApiError } from '../api/errors';
import { usePortal } from '../state/PortalContext';

export const PROGRAM_UNAVAILABLE_MESSAGE =
  "The partner program isn't available yet. Please try again later.";
export const FEATURE_UNAVAILABLE_MESSAGE = 'This feature is not available yet.';
export const OTP_DELIVERY_UNAVAILABLE_MESSAGE =
  "We can't send a sign-in code to this number yet.";

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
    // The contract: `503 AGENT_PROGRAM_UNAVAILABLE` while the program isn't
    // set up, and with it switched off the routes don't exist at all (a 404
    // with no `code` — every documented 404 carries one). Either way, "not
    // available yet" rather than Nest's "Cannot POST /agent/…".
    if (
      error.code === 'AGENT_PROGRAM_UNAVAILABLE' ||
      (error.status === 404 && error.code === null)
    ) {
      return PROGRAM_UNAVAILABLE_MESSAGE;
    }
    // The shared platform services' 503s (contract, "Any agent or member
    // referral route may also answer").
    if (error.code === 'IDENTIFIER_HASHING_UNAVAILABLE') {
      return FEATURE_UNAVAILABLE_MESSAGE;
    }
    if (error.code === 'OTP_DELIVERY_UNAVAILABLE') {
      return OTP_DELIVERY_UNAVAILABLE_MESSAGE;
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
