'use client';

import { RequirePermission } from '@/components/AppShell';
import { Badge, Card, ErrorState, Loading, Notice, PageHeader } from '@/components/ui';
import { formatDateTime } from '@/lib/format';
import type { RolesResponse } from '@/lib/types';
import { useApi } from '@/lib/use-api';

/**
 * Read-only view of roles, what they grant and who holds them. Viewing it
 * needs rbac.manage, a sensitive permission (fresh authenticator code).
 * Changes are made with `pnpm admin:provision` until role editing exists.
 */
export default function RolesPage() {
  return (
    <RequirePermission permission="rbac.manage">
      <Roles />
    </RequirePermission>
  );
}

function Roles() {
  const data = useApi((api) => api.get<RolesResponse>('/admin/roles'), []);

  return (
    <>
      <PageHeader
        title="Roles & permissions"
        description="Who can do what. Every permission is checked by the API on every request."
      />
      <Notice>
        Admins and role assignments are managed by an operator with{' '}
        <code>pnpm admin:provision</code> (grant, revoke, reset authenticator, deactivate) —
        see docs/admin/README.md. Editing roles here comes later.
      </Notice>
      {data.loading && !data.data ? <Loading /> : null}
      {data.error ? <ErrorState message={data.error} onRetry={data.reload} /> : null}
      {data.data?.roles.map((role) => (
        <Card
          key={role.key}
          title={
            <>
              {role.name} <code className="small">{role.key}</code>{' '}
              {role.isSystem ? <Badge value="DRAFT" label="system" /> : null}
            </>
          }
        >
          {role.description ? <p>{role.description}</p> : null}
          <h3>Admins ({role.admins.length})</h3>
          {role.admins.length === 0 ? (
            <p className="muted">Nobody holds this role.</p>
          ) : (
            <ul className="kv">
              {role.admins.map((admin) => (
                <li key={admin.email}>
                  <span>
                    {admin.email}{' '}
                    {!admin.active ? <Badge value="CANCELLED" label="inactive" /> : null}
                    {!admin.authenticatorEnrolled ? (
                      <Badge value="PENDING" label="no authenticator yet" />
                    ) : null}
                  </span>
                  <span className="muted small">
                    last sign-in {formatDateTime(admin.lastLoginAt)}
                  </span>
                </li>
              ))}
            </ul>
          )}
          <details>
            <summary>{role.permissions.length} permissions</summary>
            <ul className="chips">
              {role.permissions.map((key) => {
                const sensitive = data.data?.permissions.find((p) => p.key === key)?.isSensitive;
                return (
                  <li key={key}>
                    <code>{key}</code>
                    {sensitive ? <span className="muted small"> (sensitive)</span> : null}
                  </li>
                );
              })}
            </ul>
          </details>
        </Card>
      ))}
    </>
  );
}
