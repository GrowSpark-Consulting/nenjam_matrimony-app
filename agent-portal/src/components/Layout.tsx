import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { pickLabel, statusTone } from '../lib/labels';
import { usePortal } from '../state/PortalContext';
import { ErrorText } from './ErrorText';
import { Loading } from './Loading';
import { Icon, StatusBadge, type IconName } from './ui';

interface NavItem {
  to: string;
  label: string;
  icon: IconName;
  end?: boolean;
}

/** Signed-in agent shell: sidebar on wide screens, header + tab bar on phones. */
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
  const doSignOut = () => void signOut().then(() => navigate('/sign-in', { replace: true }));

  return (
    <div className="shell">
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <header className="sidebar">
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
      </header>
      <div className="content">
        {usingMocks && <MockBanner />}
        <main className="main" id="main" tabIndex={-1}>
          {/* Secondary requests fail on their own: the page below stays usable. */}
          {agent && loading && <Loading label="Refreshing your account…" lines={1} />}
          {agent && <ErrorText error={agentError} onRetry={retryAgent} />}
          {configLoading && !config && <Loading label="Loading labels…" lines={1} />}
          <ErrorText error={configError} onRetry={retryConfig} />
          <Outlet />
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
