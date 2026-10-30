/** Shown where the server hasn't deployed the endpoint yet (not an error). */
export function ComingSoon({ what }: { what: string }) {
  return (
    <p className="hint" role="status">
      {what} will be available here soon.
    </p>
  );
}
