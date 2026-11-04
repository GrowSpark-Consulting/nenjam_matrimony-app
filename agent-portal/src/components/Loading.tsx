import { Skeleton } from './ui';

/** A polite, screen-reader-announced loading line with a quiet placeholder. */
export function Loading({ label = 'Loading…', lines = 2 }: { label?: string; lines?: number }) {
  return (
    <div className="loading" role="status" aria-live="polite">
      <span className="hint">{label}</span>
      <Skeleton lines={lines} />
    </div>
  );
}
