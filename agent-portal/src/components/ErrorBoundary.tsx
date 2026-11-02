import { Component, type ErrorInfo, type ReactNode } from 'react';

interface Props {
  children: ReactNode;
  /** Wrap the whole screen (true) or just a page inside the shell (false). */
  fullScreen?: boolean;
}

/**
 * Catches an exception thrown while rendering, so one unexpected API response
 * shows a message instead of a blank page. The responses are typed but not
 * validated at runtime, so a field the backend omits can throw in a page.
 *
 * Shows a fixed sentence only: never the error text, which could carry
 * server data. The session is untouched, so "Reload" returns to the same page.
 */
export class ErrorBoundary extends Component<Props, { failed: boolean }> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  componentDidCatch(_error: Error, _info: ErrorInfo) {
    // React already reports the error to the console in development; nothing
    // is logged or sent from here.
  }

  render() {
    if (!this.state.failed) return this.props.children;
    const box = (
      <div className="error-box" role="alert">
        <p className="error">Something went wrong showing this page.</p>
        <button type="button" className="secondary" onClick={() => window.location.reload()}>
          Reload
        </button>
      </div>
    );
    return this.props.fullScreen ? (
      <div className="app">
        <main className="main narrow">{box}</main>
      </div>
    ) : (
      box
    );
  }
}
