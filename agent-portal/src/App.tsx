import type { ReactElement } from 'react';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import type { AgentStatus } from './api/types';
import { Layout } from './components/Layout';
import { ApplyPage } from './pages/ApplyPage';
import { HelpPage } from './pages/HelpPage';
import { HomePage } from './pages/HomePage';
import { EarningsPage, PayoutsPage } from './pages/MoneyPages';
import { PayoutDetailsPage } from './pages/PayoutDetailsPage';
import { ReferralsPage } from './pages/ReferralsPage';
import { SignInPage } from './pages/SignInPage';
import { StatusPage } from './pages/StatusPage';
import { usePortal } from './state/PortalContext';

/** Where an agent of [status] lands (the contract's state table). */
export function homeFor(status: AgentStatus): string {
  switch (status) {
    case 'ACTIVE':
    case 'SUSPENDED':
      return '/';
    case 'TERMINATED':
      return '/earnings';
    default:
      return '/status';
  }
}

/** Gate: signed in, the right scope, and a status allowed on this screen. */
function Guard({ allow, children }: { allow?: AgentStatus[]; children: ReactElement }) {
  const { stored, agent, loading } = usePortal();
  if (!stored) return <Navigate to="/sign-in" replace />;
  if (stored.session.scope === 'APPLICANT') return <Navigate to="/apply" replace />;
  if (loading && !agent) return <p className="main">Loading…</p>;
  if (!agent) return <Navigate to="/sign-in" replace />;
  if (allow && !allow.includes(agent.status)) return <Navigate to={homeFor(agent.status)} replace />;
  return children;
}

/** The application form: a new applicant, or a rejected agent applying again. */
function ApplyGuard({ children }: { children: ReactElement }) {
  const { stored, agent, loading } = usePortal();
  if (!stored) return <Navigate to="/sign-in" replace />;
  if (stored.session.scope === 'APPLICANT') return children;
  if (loading && !agent) return <p className="main">Loading…</p>;
  if (agent?.status !== 'REJECTED') return <Navigate to="/" replace />;
  return children;
}

const REFERRAL_STATUSES: AgentStatus[] = ['ACTIVE', 'SUSPENDED'];
const MONEY_STATUSES: AgentStatus[] = ['ACTIVE', 'SUSPENDED', 'TERMINATED'];

export function AppRoutes() {
  const { stored } = usePortal();
  return (
    <Routes>
      <Route path="/sign-in" element={<SignInPage />} />
      <Route path="/apply" element={<ApplyGuard><ApplyPage /></ApplyGuard>} />
      <Route element={stored ? <Guard><Layout /></Guard> : undefined}>
        <Route path="/" element={<Guard allow={REFERRAL_STATUSES}><HomePage /></Guard>} />
        <Route path="/referrals" element={<Guard allow={REFERRAL_STATUSES}><ReferralsPage /></Guard>} />
        <Route path="/earnings" element={<Guard allow={MONEY_STATUSES}><EarningsPage /></Guard>} />
        <Route path="/payouts" element={<Guard allow={MONEY_STATUSES}><PayoutsPage /></Guard>} />
        <Route path="/payout-details" element={<Guard allow={['ACTIVE']}><PayoutDetailsPage /></Guard>} />
        <Route path="/status" element={<Guard><StatusPage /></Guard>} />
        <Route path="/help" element={<HelpPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export function App() {
  return (
    <BrowserRouter>
      <AppRoutes />
    </BrowserRouter>
  );
}
