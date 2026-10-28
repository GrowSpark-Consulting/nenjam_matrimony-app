'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState, type ReactNode } from 'react';
import { can, visibleNav } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import { StepUpDialog } from './StepUpDialog';
import { Button, ErrorState, Loading } from './ui';

/**
 * The signed-in frame: sidebar navigation built from the admin's permissions
 * (presentation only — the API re-checks every request), header and sign-out.
 * Anyone who isn't fully signed in is sent to the right step.
 */
export function AppShell({ children }: { children: ReactNode }) {
  const session = useSession();
  const router = useRouter();
  const pathname = usePathname();
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    if (session.phase === 'signedOut' || session.phase === 'unconfigured') {
      router.replace('/login/');
    } else if (session.phase === 'secondFactor') {
      router.replace('/verify/');
    }
  }, [session.phase, router]);

  useEffect(() => setMenuOpen(false), [pathname]);

  if (session.phase === 'error') {
    return (
      <main className="centered">
        <ErrorState message={session.error ?? 'Something went wrong.'} onRetry={session.retry} />
      </main>
    );
  }
  if (session.phase === 'notStaff') {
    return (
      <main className="centered">
        <div className="auth-card">
          <h1>No admin access</h1>
          <p>
            {session.email ?? 'This account'} is not an active admin. Admin accounts are
            created by a Super Admin; ask them if you should have access.
          </p>
          <Button onClick={() => void session.signOut()}>Sign out</Button>
        </div>
      </main>
    );
  }
  if (session.phase !== 'ready' || !session.me) return <Loading />;

  const me = session.me;
  const nav = visibleNav(me.permissions);
  let lastGroup: string | undefined;

  return (
    <div className="shell">
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <aside className={`sidebar ${menuOpen ? 'open' : ''}`} aria-label="Sections">
        <div className="brand">Nenjam Admin</div>
        <nav>
          {nav.length === 0 ? (
            <p className="muted small">Your roles don’t include any section yet.</p>
          ) : null}
          {nav.map((item) => {
            const heading = item.group && item.group !== lastGroup ? item.group : null;
            lastGroup = item.group;
            const active =
              item.href === '/' ? pathname === '/' : pathname.startsWith(item.href);
            return (
              <div key={item.href}>
                {heading ? <div className="nav-group">{heading}</div> : null}
                <Link
                  href={item.href}
                  className={`nav-link ${active ? 'active' : ''}`}
                  aria-current={active ? 'page' : undefined}
                >
                  {item.label}
                </Link>
              </div>
            );
          })}
        </nav>
      </aside>
      <div className="main-col">
        <header className="topbar">
          <button
            type="button"
            className="menu-toggle"
            aria-expanded={menuOpen}
            aria-label="Menu"
            onClick={() => setMenuOpen((open) => !open)}
          >
            ☰
          </button>
          <div className="topbar-who">
            <span>{me.email}</span>
            <span className="muted small">
              {me.roles.map((r) => r.name).join(', ') || 'No role'}
            </span>
          </div>
          <Button tone="ghost" onClick={() => void session.signOut()}>
            Sign out
          </Button>
        </header>
        <main id="main" className="content">
          {children}
        </main>
      </div>
      <StepUpDialog />
    </div>
  );
}

/**
 * Hides a page from admins without [permission]. The API refuses them anyway;
 * this just shows a clear page instead of an error.
 */
export function RequirePermission({
  permission,
  children,
}: {
  permission: string;
  children: ReactNode;
}) {
  const { me } = useSession();
  if (!can(me?.permissions, permission)) {
    return <AccessDenied permission={permission} />;
  }
  return <>{children}</>;
}

export function AccessDenied({ permission }: { permission?: string }) {
  return (
    <div className="state empty" role="alert">
      <strong>You don’t have access to this page.</strong>
      <span className="muted">
        {permission ? (
          <>
            It needs the <code>{permission}</code> permission.{' '}
          </>
        ) : null}
        Ask a Super Admin if your role should include it.
      </span>
    </div>
  );
}
