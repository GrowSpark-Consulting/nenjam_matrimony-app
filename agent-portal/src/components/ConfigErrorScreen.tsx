/** Shown instead of the portal when the build is misconfigured. */
export function ConfigErrorScreen({ reason }: { reason: string }) {
  return (
    <main className="main narrow">
      <h1>Nenjam Partner Program</h1>
      <p role="alert">The portal isn't available right now. Please try again later.</p>
      <p className="hint">Configuration problem: {reason}</p>
    </main>
  );
}
