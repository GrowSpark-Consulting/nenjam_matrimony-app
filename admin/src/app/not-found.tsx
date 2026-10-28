import Link from 'next/link';

export default function NotFound() {
  return (
    <main className="centered">
      <div className="auth-card">
        <h1>Page not found</h1>
        <Link href="/">Back to the admin panel</Link>
      </div>
    </main>
  );
}
