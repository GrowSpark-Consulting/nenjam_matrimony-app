'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { Suspense, useState } from 'react';
import { RequirePermission } from '@/components/AppShell';
import {
  Badge,
  Button,
  Card,
  ConfirmDialog,
  EmptyState,
  ErrorState,
  Field,
  Loading,
  PageHeader,
  useToast,
} from '@/components/ui';
import { formatDate, humanize } from '@/lib/format';
import { readFilter, USER_STATUSES } from '@/lib/links';
import { can } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type {
  AdminUserListItem,
  AdminUserListResponse,
  AdminUserStats,
  BlockUserResult,
  UnblockUserResult,
} from '@/lib/types';
import { useApi } from '@/lib/use-api';

interface UserFilters {
  search: string;
  gender: string;
  status: string;
  membership: string;
  profileComplete: string;
  sortBy: string;
  sortOrder: string;
}

export default function UsersPage() {
  return (
    <RequirePermission permission="member.view">
      <Suspense fallback={<Loading />}>
        <UsersFromAddress />
      </Suspense>
    </RequirePermission>
  );
}

function UsersFromAddress() {
  const params = useSearchParams();
  const initial: UserFilters = {
    search: params.get('search') ?? '',
    gender: params.get('gender') ?? '',
    status: readFilter(params, 'status', USER_STATUSES),
    membership: params.get('membership') ?? '',
    profileComplete: params.get('profileComplete') ?? '',
    sortBy: params.get('sortBy') ?? 'createdAt',
    sortOrder: params.get('sortOrder') ?? 'desc',
  };
  return <UserManagement key={params.toString()} initial={initial} />;
}

function UserManagement({ initial }: { initial: UserFilters }) {
  const { api, me } = useSession();
  const toast = useToast();

  const [draft, setDraft] = useState<UserFilters>(initial);
  const [filters, setFilters] = useState<UserFilters>(initial);
  const [page, setPage] = useState(1);

  // Dialog actions
  const [targetUser, setTargetUser] = useState<AdminUserListItem | null>(null);
  const [pendingAction, setPendingAction] = useState<'block' | 'unblock' | null>(null);

  const canSuspend = can(me?.permissions, 'member.suspend');

  // 1. User Aggregate Statistics
  const stats = useApi((client) => client.get<AdminUserStats>('/admin/users/stats'), []);

  // 2. User Directory Query
  const userList = useApi(
    (client) =>
      client.get<AdminUserListResponse>('/admin/users', {
        page,
        limit: 20,
        search: filters.search || undefined,
        gender: filters.gender || undefined,
        status: filters.status || undefined,
        membership: filters.membership || undefined,
        profileComplete: filters.profileComplete || undefined,
        sortBy: filters.sortBy || undefined,
        sortOrder: filters.sortOrder || undefined,
      }),
    [page, filters],
  );

  const handleTileClick = (newStatus: string) => {
    const nextStatus = filters.status === newStatus ? '' : newStatus;
    const next = { ...filters, status: nextStatus };
    setDraft(next);
    setFilters(next);
    setPage(1);
  };

  const handleSearchSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setPage(1);
    setFilters(draft);
  };

  const handleResetFilters = () => {
    const reset: UserFilters = {
      search: '',
      gender: '',
      status: '',
      membership: '',
      profileComplete: '',
      sortBy: 'createdAt',
      sortOrder: 'desc',
    };
    setDraft(reset);
    setFilters(reset);
    setPage(1);
  };

  const handleBlockConfirm = async (reason: string) => {
    if (!targetUser) return;
    try {
      await api.patch<BlockUserResult>(`/admin/users/${targetUser.id}/block`, {
        reason,
      });
      toast('success', `User ${targetUser.fullName || targetUser.id} has been blocked.`);
      userList.reload();
      stats.reload();
    } catch (err) {
      toast('error', err instanceof Error ? err.message : 'Failed to block user.');
      throw err;
    }
  };

  const handleUnblockConfirm = async (reason: string) => {
    if (!targetUser) return;
    try {
      await api.patch<UnblockUserResult>(`/admin/users/${targetUser.id}/unblock`, {
        reason: reason.trim() || undefined,
      });
      toast('success', `User ${targetUser.fullName || targetUser.id} has been unblocked.`);
      userList.reload();
      stats.reload();
    } catch (err) {
      toast('error', err instanceof Error ? err.message : 'Failed to unblock user.');
      throw err;
    }
  };

  return (
    <>
      <PageHeader
        title="User Management"
        description="Search, view profiles, and manage member account statuses. Contact details are masked."
      />

      {/* Aggregate Statistics Dashboard */}
      <Card title="Member Overview">
        {stats.loading && !stats.data ? <Loading label="Loading user statistics…" /> : null}
        {stats.error ? <ErrorState message={stats.error} onRetry={stats.reload} /> : null}
        {stats.data ? (
          <div className="status-tiles">
            <button
              type="button"
              className={`status-tile ${filters.status === '' ? 'status-tile-selected' : ''}`}
              onClick={() => handleTileClick('')}
              aria-pressed={filters.status === ''}
            >
              <span className="status-tile-value">
                {stats.data.totalUsers.toLocaleString('en-IN')}
              </span>
              <span className="status-tile-label">Total Registered</span>
            </button>

            <button
              type="button"
              className={`status-tile ${filters.status === 'ACTIVE' ? 'status-tile-selected' : ''}`}
              onClick={() => handleTileClick('ACTIVE')}
              aria-pressed={filters.status === 'ACTIVE'}
            >
              <span className="status-tile-value">
                {stats.data.activeUsers.toLocaleString('en-IN')}
              </span>
              <span className="status-tile-label">Active Users</span>
            </button>

            <button
              type="button"
              className={`status-tile ${filters.status === 'BLOCKED' ? 'status-tile-selected' : ''}`}
              onClick={() => handleTileClick('BLOCKED')}
              aria-pressed={filters.status === 'BLOCKED'}
            >
              <span className="status-tile-value">
                {stats.data.blockedUsers.toLocaleString('en-IN')}
              </span>
              <span className="status-tile-label">Blocked Users</span>
            </button>

            <div className="status-tile" style={{ cursor: 'default' }}>
              <span className="status-tile-value">
                {stats.data.registeredToday.toLocaleString('en-IN')}
              </span>
              <span className="status-tile-label">Registered Today</span>
            </div>

            <button
              type="button"
              className={`status-tile ${filters.profileComplete === 'false' ? 'status-tile-selected' : ''}`}
              onClick={() => {
                const nextVal = filters.profileComplete === 'false' ? '' : 'false';
                setDraft({ ...draft, profileComplete: nextVal });
                setFilters({ ...filters, profileComplete: nextVal });
                setPage(1);
              }}
              aria-pressed={filters.profileComplete === 'false'}
            >
              <span className="status-tile-value">
                {stats.data.incompleteProfiles.toLocaleString('en-IN')}
              </span>
              <span className="status-tile-label">Incomplete Profiles</span>
            </button>

            <button
              type="button"
              className={`status-tile ${filters.membership === 'GOLD' ? 'status-tile-selected' : ''}`}
              onClick={() => {
                const nextMem = filters.membership === 'GOLD' ? '' : 'GOLD';
                setDraft({ ...draft, membership: nextMem });
                setFilters({ ...filters, membership: nextMem });
                setPage(1);
              }}
              aria-pressed={filters.membership === 'GOLD'}
            >
              <span className="status-tile-value">
                {stats.data.premiumMembers.toLocaleString('en-IN')}
              </span>
              <span className="status-tile-label">Premium Members</span>
            </button>
          </div>
        ) : null}
      </Card>

      {/* Search and Filters */}
      <Card>
        <form className="filters" onSubmit={handleSearchSubmit}>
          <Field
            label="Search"
            hint="Search by Member ID, full name, email, or phone digits"
          >
            {(props) => (
              <input
                {...props}
                type="search"
                placeholder="e.g. Karthik, +91 98..., user@domain.com"
                value={draft.search}
                onChange={(e) => setDraft({ ...draft, search: e.target.value })}
              />
            )}
          </Field>

          <Field label="Status">
            {(props) => (
              <select
                {...props}
                value={draft.status}
                onChange={(e) => setDraft({ ...draft, status: e.target.value })}
              >
                <option value="">Any Status</option>
                <option value="ACTIVE">Active</option>
                <option value="BLOCKED">Blocked</option>
                <option value="SUSPENDED">Suspended</option>
                <option value="PENDING_VERIFICATION">Pending Verification</option>
                <option value="DEACTIVATED">Deactivated</option>
                <option value="BANNED">Banned</option>
              </select>
            )}
          </Field>

          <Field label="Gender">
            {(props) => (
              <select
                {...props}
                value={draft.gender}
                onChange={(e) => setDraft({ ...draft, gender: e.target.value })}
              >
                <option value="">Any Gender</option>
                <option value="MALE">Male</option>
                <option value="FEMALE">Female</option>
              </select>
            )}
          </Field>

          <Field label="Membership">
            {(props) => (
              <select
                {...props}
                value={draft.membership}
                onChange={(e) => setDraft({ ...draft, membership: e.target.value })}
              >
                <option value="">Any Plan</option>
                <option value="FREE">Free</option>
                <option value="GOLD">Gold</option>
                <option value="PLATINUM">Platinum</option>
              </select>
            )}
          </Field>

          <Field label="Profile">
            {(props) => (
              <select
                {...props}
                value={draft.profileComplete}
                onChange={(e) =>
                  setDraft({ ...draft, profileComplete: e.target.value })
                }
              >
                <option value="">Any Completeness</option>
                <option value="true">100% Complete</option>
                <option value="false">Incomplete</option>
              </select>
            )}
          </Field>

          <Field label="Sort By">
            {(props) => (
              <select
                {...props}
                value={draft.sortBy}
                onChange={(e) => setDraft({ ...draft, sortBy: e.target.value })}
              >
                <option value="createdAt">Registration Date</option>
                <option value="name">Member Name</option>
                <option value="status">Status</option>
              </select>
            )}
          </Field>

          <Field label="Order">
            {(props) => (
              <select
                {...props}
                value={draft.sortOrder}
                onChange={(e) => setDraft({ ...draft, sortOrder: e.target.value })}
              >
                <option value="desc">Newest / Z–A</option>
                <option value="asc">Oldest / A–Z</option>
              </select>
            )}
          </Field>

          <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'flex-end' }}>
            <Button type="submit" tone="primary">
              Filter
            </Button>
            <Button onClick={handleResetFilters}>
              Reset
            </Button>
          </div>
        </form>
      </Card>

      {/* Member Directory Table */}
      <Card>
        {userList.loading && !userList.data ? <Loading label="Loading members…" /> : null}
        {userList.error ? (
          <ErrorState message={userList.error} onRetry={userList.reload} />
        ) : null}

        {userList.data && userList.data.items.length === 0 ? (
          <EmptyState title="No members found">
            Try adjusting your search query, status filters, or profile completeness criteria.
          </EmptyState>
        ) : null}

        {userList.data && userList.data.items.length > 0 ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">Member</th>
                  <th scope="col">Gender / Age</th>
                  <th scope="col">Location</th>
                  <th scope="col">Contacts</th>
                  <th scope="col">Plan</th>
                  <th scope="col">Profile</th>
                  <th scope="col">Account Status</th>
                  <th scope="col">Registered</th>
                  <th scope="col" style={{ textAlign: 'right' }}>
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody>
                {userList.data.items.map((user) => (
                  <tr key={user.id}>
                    <td>
                      <Link
                        href={`/users/${user.id}`}
                        style={{ fontWeight: 600, textDecoration: 'none' }}
                      >
                        {user.fullName || 'Incomplete Profile'}
                      </Link>
                      <div className="muted small font-mono">
                        {user.id.slice(0, 8)}…
                      </div>
                    </td>
                    <td>
                      {user.gender ? humanize(user.gender) : '—'}
                      {user.age ? <span className="muted small"> · {user.age} yrs</span> : null}
                    </td>
                    <td>{user.location || '—'}</td>
                    <td>
                      <div>{user.phone || '—'}</div>
                      <div className="muted small">{user.email || '—'}</div>
                    </td>
                    <td>
                      <Badge
                        value={user.membershipCode}
                        label={user.membership}
                      />
                    </td>
                    <td>
                      <Badge
                        value={user.profileStatus}
                        label={`${user.profileCompletePct}%`}
                      />
                    </td>
                    <td>
                      <Badge value={user.accountStatus} />
                    </td>
                    <td className="nowrap">{formatDate(user.registrationDate)}</td>
                    <td style={{ textAlign: 'right' }}>
                      <div
                        style={{
                          display: 'inline-flex',
                          gap: '0.4rem',
                          justifyContent: 'flex-end',
                        }}
                      >
                        <Link href={`/users/${user.id}`}>
                          <Button tone="ghost" className="small">
                            View
                          </Button>
                        </Link>

                        {canSuspend ? (
                          user.accountStatus === 'BLOCKED' ? (
                            <Button
                              tone="secondary"
                              className="small"
                              onClick={() => {
                                setTargetUser(user);
                                setPendingAction('unblock');
                              }}
                            >
                              Unblock
                            </Button>
                          ) : (
                            <Button
                              tone="danger"
                              className="small"
                              onClick={() => {
                                setTargetUser(user);
                                setPendingAction('block');
                              }}
                            >
                              Block
                            </Button>
                          )
                        ) : null}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}

        {/* Server-Side Pagination */}
        {userList.data ? (
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              marginTop: '1rem',
              flexWrap: 'wrap',
              gap: '0.5rem',
            }}
          >
            <div className="muted small">
              Page {userList.data.page} of {Math.max(1, userList.data.totalPages)} (
              {userList.data.total.toLocaleString('en-IN')} members total)
            </div>
            <div className="pager" style={{ margin: 0 }}>
              <Button
                disabled={page <= 1 || userList.loading}
                onClick={() => setPage((p) => Math.max(1, p - 1))}
              >
                Previous
              </Button>
              <Button
                disabled={page >= userList.data.totalPages || userList.loading}
                onClick={() => setPage((p) => p + 1)}
              >
                Next
              </Button>
            </div>
          </div>
        ) : null}
      </Card>

      {/* Block Confirmation Dialog */}
      <ConfirmDialog
        open={pendingAction === 'block'}
        title={`Block User: ${targetUser?.fullName || targetUser?.id || ''}`}
        confirmLabel="Block Member"
        tone="danger"
        requireReason={true}
        reasonLabel="Reason for blocking (recorded in audit log)"
        onConfirm={handleBlockConfirm}
        onClose={() => {
          setPendingAction(null);
          setTargetUser(null);
        }}
      >
        <p>
          Blocking this member will immediately suspend their account, invalidate their
          active sessions in Redis, and hide their profile from the matrimony app.
        </p>
      </ConfirmDialog>

      {/* Unblock Confirmation Dialog */}
      <ConfirmDialog
        open={pendingAction === 'unblock'}
        title={`Unblock User: ${targetUser?.fullName || targetUser?.id || ''}`}
        confirmLabel="Unblock Member"
        tone="primary"
        requireReason={false}
        reasonLabel="Optional note for unblocking"
        onConfirm={handleUnblockConfirm}
        onClose={() => {
          setPendingAction(null);
          setTargetUser(null);
        }}
      >
        <p>
          Unblocking will restore this member’s account status to <strong>ACTIVE</strong>,
          allowing them to sign in and interact on Nenjam Matrimony again.
        </p>
      </ConfirmDialog>
    </>
  );
}
