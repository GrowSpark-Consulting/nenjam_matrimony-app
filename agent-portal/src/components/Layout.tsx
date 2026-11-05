import { useEffect, useRef, useState } from 'react';
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom';
import { clientsAvailable } from '../lib/clientsFeature';
import { pickLabel, statusTone } from '../lib/labels';
import { usePortal } from '../state/PortalContext';
import { ErrorBoundary } from './ErrorBoundary';
import { ErrorText } from './ErrorText';
import { Loading } from './Loading';
import { Icon, StatusBadge, type IconName } from './ui';

interface NavItem {
  to: string;
  label: string;
  icon: IconName;
  end?: boolean;
}

const WIDE = '(min-width: 900px)';

/** True below the breakpoint where the sidebar turns into a drawer. */
function useDrawerMode(): boolean {
  const query = typeof window !== 'undefined' && window.matchMedia ? window.matchMedia(WIDE) : null;
  const [wide, setWide] = useState(query ? query.matches : true);
  useEffect(() => {
    if (!query) return;
    const on = () => setWide(query.matches);
    on();
    query.addEventListener('change', on);
    return () => query.removeEventListener('change', on);
  }, [query]);
  return !wide;
}

/** Signed-in agent shell: sidebar on wide screens, top bar + drawer below 900px. */
export function Layout() {
  const {
    agent,
    config,
    signOut,
    usingMocks,
    loading,
    configLoading,
    agentError,
    configError,
    retryAgent,
    retryConfig,
  } = usePortal();
  const navigate = useNavigate();
  const location = useLocation();
  const status = agent?.status;
  const canSeeReferrals = status === 'ACTIVE' || status === 'SUSPENDED';
  const canSeeMoney = canSeeReferrals || status === 'TERMINATED';

  const groups: { title: string; items: NavItem[] }[] = [];
  if (canSeeReferrals) {
    groups.push({
      title: 'Referrals',
      items: [
        { to: '/', label: 'Home', icon: 'home', end: true },
        { to: '/referrals', label: 'People who joined', icon: 'people' },
        ...(clientsAvailable(config, agent)
          ? [{ to: '/clients', label: 'Your clients', icon: 'people' as IconName }]
          : []),
      ],
    });
  }
  if (canSeeMoney) {
    const items: NavItem[] = [
      { to: '/earnings', label: 'Earnings', icon: 'coins' },
      { to: '/payouts', label: 'Payouts', icon: 'wallet' },
    ];
    if (status === 'ACTIVE') items.push({ to: '/payout-details', label: 'Payout details', icon: 'bank' });
    groups.push({ title: 'Money', items });
  }
  const support: NavItem[] = [];
  if (!canSeeReferrals) support.push({ to: '/status', label: 'Status', icon: 'status' });
  support.push({ to: '/help', label: 'Help', icon: 'help' });
  groups.push({ title: 'Support', items: support });

  const statusText = agent
    ? pickLabel(config?.statusLabels[agent.status] ?? agent.statusLabel, agent.status)
    : null;
  const drawerMode = useDrawerMode();
  // Open is tied to the route it was opened on, so navigating closes it.
  const [openAt, setOpenAt] = useState<string | null>(null);
  const open = openAt === location.pathname;
  const setOpen = (v: boolean | ((o: boolean) => boolean)) =>
    setOpenAt((cur) => ((typeof v === 'function' ? v(cur === location.pathname) : v) ? location.pathname : null));
  const menuButton = useRef<HTMLButtonElement>(null);
  const drawerOpen = drawerMode && open;

  // Lock page scroll behind the open drawer; Escape closes it and returns focus.
  useEffect(() => {
    if (!drawerOpen) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setOpen(false);
        menuButton.current?.focus();
      }
    };
    document.addEventListener('keydown', onKey);
    return () => {
      document.body.style.overflow = prev;
      document.removeEventListener('keydown', onKey);
    };
  }, [drawerOpen]);

  const doSignOut = () => void signOut().then(() => navigate('/sign-in', { replace: true }));

  return (
    <div className="shell">
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      {drawerMode && (
        <header className="topbar">
          <button
            ref={menuButton}
            type="button"
            className="menu-button"
            aria-label={drawerOpen ? 'Close menu' : 'Open menu'}
            aria-expanded={drawerOpen}
            aria-controls="portal-nav"
            onClick={() => setOpen((o) => !o)}
          >
            <Icon name={drawerOpen ? 'close' : 'menu'} size={22} />
          </button>
          <div className="brand">
            <span className="brand-mark" aria-hidden="true">N</span>
            <span className="brand-title">Nenjam Partner</span>
          </div>
        </header>
      )}
      {drawerOpen && <div className="backdrop" onClick={() => setOpen(false)} aria-hidden="true" />}
      <aside
        id="portal-nav"
        className={`sidebar${drawerMode ? ' drawer' : ''}${drawerOpen ? ' open' : ''}`}
        aria-label="Menu"
        // A closed drawer is off-screen: keep it out of the tab order too.
        inert={drawerMode && !drawerOpen ? true : undefined}
      >
        <div className="brand">
          <span className="brand-mark" aria-hidden="true">N</span>
          <span className="brand-name">Nenjam Partner Program</span>
        </div>
        {agent && (
          <div className="identity">
            <span className="avatar" aria-hidden="true">{agent.name.trim().charAt(0).toUpperCase()}</span>
            <div className="identity-text">
              <span className="identity-name" title={agent.name}>{agent.name}</span>
              <StatusBadge tone={statusTone(agent.status)}>{statusText}</StatusBadge>
            </div>
          </div>
        )}
        <nav className="nav" aria-label="Main">
          {groups.map((g) => (
            <div className="nav-group" key={g.title}>
              <p className="nav-group-title" aria-hidden="true">{g.title}</p>
              {g.items.map((i) => (
                <NavLink key={i.to} to={i.to} end={i.end}>
                  <Icon name={i.icon} />
                  <span>{i.label}</span>
                </NavLink>
              ))}
            </div>
          ))}
        </nav>
        <button type="button" className="signout" onClick={doSignOut}>
          <Icon name="signout" size={18} />
          Sign out
        </button>
      </aside>
      <div className="content">
        {usingMocks && <MockBanner />}
        <main className="main" id="main" tabIndex={-1}>
          {/* Secondary requests fail on their own: the page below stays usable. */}
          {agent && loading && <Loading label="Refreshing your account…" lines={1} />}
          {agent && <ErrorText error={agentError} onRetry={retryAgent} />}
          {configLoading && !config && <Loading label="Loading labels…" lines={1} />}
          <ErrorText error={configError} onRetry={retryConfig} />
          {/* Keyed by route: leaving a page that failed to render clears it. */}
          <ErrorBoundary key={location.pathname}>
            <Outlet />
          </ErrorBoundary>
        </main>
      </div>
    </div>
  );
}

export function MockBanner() {
  return (
    <p className="mock-banner" role="note">
      Test mode: this portal is using sample data, not the live service.
    </p>
  );
}
