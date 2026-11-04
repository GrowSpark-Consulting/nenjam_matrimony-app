'use client';

import { useState } from 'react';
import { RequirePermission } from '@/components/AppShell';
import {
  Button,
  Card,
  ConfirmDialog,
  EmptyState,
  ErrorState,
  Field,
  Loading,
  Notice,
  PageHeader,
  useToast,
} from '@/components/ui';
import { ApiError } from '@/lib/api';
import { formatDateTime } from '@/lib/format';
import { can } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import {
  SETTING_KINDS,
  formatSettingValue,
  groupSettings,
  parseSettingInput,
  sameSettingValue,
  settingInputText,
  settingKindOf,
  type PlatformSetting,
  type SettingKind,
  type SettingsResponse,
} from '@/lib/settings';
import { useApi } from '@/lib/use-api';

/**
 * Platform settings (rates, limits, feature switches). Viewing needs
 * system.view; changing one needs config.edit, a reason and a fresh
 * authenticator code. The API checks the version that was read (409 if
 * someone changed it since), validates the value for that key, and audits
 * the old and new value in the same transaction. Values apply on the next
 * request: there is no deploy and no cache.
 */
export default function SettingsPage() {
  return (
    <RequirePermission permission="system.view">
      <Settings />
    </RequirePermission>
  );
}

function Settings() {
  const { api, me } = useSession();
  const toast = useToast();
  const data = useApi((client) => client.get<SettingsResponse>('/admin/settings'), []);
  const [target, setTarget] = useState<PlatformSetting | null>(null);
  const [kind, setKind] = useState<SettingKind>('text');
  const [raw, setRaw] = useState('');
  const canEdit = can(me?.permissions, 'config.edit');

  const open = (setting: PlatformSetting) => {
    const initial = settingKindOf(setting.value);
    setKind(initial);
    setRaw(settingInputText(initial, setting.value));
    setTarget(setting);
  };
  const changeKind = (next: SettingKind) => {
    setKind(next);
    setRaw(settingInputText(next, target?.value ?? null));
  };

  const parsed = parseSettingInput(kind, raw);
  const unchanged = target !== null && parsed.ok && sameSettingValue(parsed.value, target.value);

  return (
    <>
      <PageHeader
        title="Settings"
        description="Business values the app reads on every request: rates, limits and feature switches."
      />
      <Notice tone="warn">
        A change applies to the next request, with no deploy. Each change needs a reason and a fresh
        code from your authenticator app, and the old and new values are kept in the audit log.
        Settings come from database migrations: they can be changed here but not added or removed.
      </Notice>
      {data.loading && !data.data ? <Loading /> : null}
      {data.error ? <ErrorState message={data.error} onRetry={data.reload} /> : null}
      {data.data && data.data.items.length === 0 ? <EmptyState title="No settings" /> : null}
      {data.data
        ? groupSettings(data.data.items).map((group) => (
            <Card key={group.group} title={group.title}>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th scope="col">Setting</th>
                      <th scope="col">Value</th>
                      <th scope="col">Last changed</th>
                      {canEdit ? (
                        <th scope="col">
                          <span className="sr-only">Actions</span>
                        </th>
                      ) : null}
                    </tr>
                  </thead>
                  <tbody>
                    {group.items.map((s) => (
                      <tr key={s.key}>
                        <td>
                          <code>{s.key}</code>
                          {s.description ? <div className="muted small">{s.description}</div> : null}
                        </td>
                        <td>
                          {s.value === null ? (
                            <span className="muted">not set</span>
                          ) : (
                            <code>{formatSettingValue(s.value)}</code>
                          )}
                        </td>
                        <td className="small">
                          {formatDateTime(s.updatedAt)}
                          <div className="muted">version {s.version}</div>
                        </td>
                        {canEdit ? (
                          <td>
                            <div className="row-actions">
                              <Button onClick={() => open(s)}>Change</Button>
                            </div>
                          </td>
                        ) : null}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </Card>
          ))
        : null}

      <ConfirmDialog
        open={target !== null}
        title={target ? `Change ${target.key}` : 'Change setting'}
        confirmLabel="Save"
        requireReason
        onClose={() => setTarget(null)}
        onConfirm={async (reason) => {
          if (!target) return;
          if (!parsed.ok) throw new Error(parsed.problem);
          if (unchanged) throw new Error('That is already the current value.');
          try {
            await api.put(`/admin/settings/${encodeURIComponent(target.key)}`, {
              value: parsed.value,
              version: target.version,
              reason,
            });
          } catch (e) {
            if (e instanceof ApiError && e.status === 409) {
              data.reload();
              throw new Error(
                'Someone changed this setting after you opened it. Close this, check the new value, and try again.',
              );
            }
            throw e;
          }
          data.reload();
          toast('success', `${target.key} is now ${formatSettingValue(parsed.value)}.`);
        }}
      >
        {target ? (
          <>
            {target.description ? <p className="muted">{target.description}</p> : null}
            <p>
              Current value:{' '}
              {target.value === null ? (
                <span className="muted">not set</span>
              ) : (
                <code>{formatSettingValue(target.value)}</code>
              )}{' '}
              <span className="muted small">(version {target.version})</span>
            </p>
            <Field label="Kind of value">
              {(props) => (
                <select
                  {...props}
                  value={kind}
                  onChange={(e) => changeKind(e.target.value as SettingKind)}
                >
                  {SETTING_KINDS.map((k) => (
                    <option key={k.kind} value={k.kind}>
                      {k.label}
                    </option>
                  ))}
                </select>
              )}
            </Field>
            {kind === 'boolean' ? (
              <Field label="New value">
                {(props) => (
                  <select {...props} value={raw} onChange={(e) => setRaw(e.target.value)}>
                    <option value="true">On (true)</option>
                    <option value="false">Off (false)</option>
                  </select>
                )}
              </Field>
            ) : null}
            {kind === 'number' ? (
              <Field label="New value" error={raw && !parsed.ok ? parsed.problem : null}>
                {(props) => (
                  <input
                    {...props}
                    inputMode="decimal"
                    value={raw}
                    onChange={(e) => setRaw(e.target.value)}
                  />
                )}
              </Field>
            ) : null}
            {kind === 'text' ? (
              <Field label="New value" hint="Leading and trailing spaces are removed.">
                {(props) => (
                  <input {...props} value={raw} onChange={(e) => setRaw(e.target.value)} />
                )}
              </Field>
            ) : null}
            {kind === 'json' ? (
              <Field label="New value (JSON)" error={raw && !parsed.ok ? parsed.problem : null}>
                {(props) => (
                  <textarea
                    {...props}
                    rows={4}
                    value={raw}
                    onChange={(e) => setRaw(e.target.value)}
                  />
                )}
              </Field>
            ) : null}
            {parsed.ok ? (
              <p className="small">
                Will be saved as <code>{JSON.stringify(parsed.value)}</code>
                {unchanged ? <span className="muted"> (the current value: nothing to change)</span> : null}
              </p>
            ) : null}
            <p className="muted small">
              The server checks the value for this setting and refuses one it can’t use. You’ll be asked
              for a code from your authenticator app if you haven’t entered one in the last 10 minutes.
            </p>
          </>
        ) : null}
      </ConfirmDialog>
    </>
  );
}
