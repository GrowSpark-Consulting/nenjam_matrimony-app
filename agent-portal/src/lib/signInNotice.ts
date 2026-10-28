/**
 * A one-time message for the sign-in screen ("your verification has expired"),
 * kept in sessionStorage so it survives the redirects that follow a session
 * being cleared. Never holds tokens or personal data.
 */
const KEY = 'nenjam.agentPortal.signInNotice';

export function setSignInNotice(message: string): void {
  try {
    window.sessionStorage.setItem(KEY, message);
  } catch {
    // Storage unavailable (private mode): the notice is simply not shown.
  }
}

export function readSignInNotice(): string | null {
  try {
    return window.sessionStorage.getItem(KEY);
  } catch {
    return null;
  }
}

export function clearSignInNotice(): void {
  try {
    window.sessionStorage.removeItem(KEY);
  } catch {
    // Nothing to clear.
  }
}
