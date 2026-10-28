import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { pickLabel } from '../lib/labels';
import { usePortal } from '../state/PortalContext';

/** Signed-in agent shell: header, status-aware navigation, sign out. */
export function Layout() {
  const { agent, config, signOut, usingMocks } = usePortal();
  const navigate = useNavigate();
  const status = agent?.status;
  const canSeeReferrals = status === 'ACTIVE' || status === 'SUSPENDED';
  const canSeeMoney = canSeeReferrals || status === 'TERMINATED';
  return (
    <div className="app">
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      {usingMocks && <MockBanner />}
      <header className="header">
        <strong>Nenjam Partner Program</strong>
        <button
          type="button"
          className="link"
          onClick={() => void signOut().then(() => navigate('/sign-in', { replace: true }))}
        >
          Sign out
        </button>
      </header>
      {agent && (
        <p className="status-line">
          {agent.name}{' '}
          <span className={`badge badge-${agent.status.toLowerCase()}`}>
            {pickLabel(config?.statusLabels[agent.status] ?? agent.statusLabel, agent.status)}
          </span>
        </p>
      )}
      <nav className="nav" aria-label="Main">
        {canSeeReferrals && (
          <NavLink to="/" end>
            Home
          </NavLink>
        )}
        {canSeeReferrals && <NavLink to="/referrals">People who joined</NavLink>}
        {canSeeMoney && <NavLink to="/earnings">Earnings</NavLink>}
        {canSeeMoney && <NavLink to="/payouts">Payouts</NavLink>}
        {status === 'ACTIVE' && <NavLink to="/payout-details">Payout details</NavLink>}
        {!canSeeReferrals && <NavLink to="/status">Status</NavLink>}
        <NavLink to="/help">Help</NavLink>
      </nav>
      <main className="main" id="main" tabIndex={-1}>
        <Outlet />
      </main>
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
