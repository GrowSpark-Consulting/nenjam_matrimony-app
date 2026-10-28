/** A polite, screen-reader-announced loading line. */
export function Loading({ label = 'Loading…' }: { label?: string }) {
  return (
    <p className="hint" role="status" aria-live="polite">
      {label}
    </p>
  );
}
