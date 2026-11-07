import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ApiError } from '../api/errors';
import type { ClientDetails, ClientDraft, ClientStatus, RefItem } from '../api/types';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { ErrorText } from '../components/ErrorText';
import { FormField, Icon, StatusBadge } from '../components/ui';
import { useAsync } from '../components/useAsync';
import {
  getPath,
  isAnswered,
  normalizeDetails,
  sectionOf,
  SECTIONS,
  setAnswer,
  setPath,
  type FieldDef,
  type SiblingRow,
} from '../lib/clientProfile';
import { clientErrorMessage, isOpen, missingText } from '../lib/clientsFeature';
import { pickLabel } from '../lib/labels';
import { usePortal } from '../state/PortalContext';

export function clientTone(s: ClientStatus) {
  return s === 'ACCEPTED' ? 'success' : s === 'DRAFT' || s === 'WAITING_FOR_CLIENT' ? 'info' : 'neutral';
}

export function initial(name: string): string {
  return name.trim().charAt(0).toUpperCase() || '?';
}

/** Order-independent compare of two normalised bodies. */
function stable(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(stable).join(',')}]`;
  if (v && typeof v === 'object') {
    return `{${Object.keys(v as object)
      .sort()
      .map((k) => `${k}:${stable((v as Record<string, unknown>)[k])}`)
      .join(',')}}`;
  }
  return JSON.stringify(v);
}

type SaveState = { kind: 'idle' } | { kind: 'saving' } | { kind: 'saved'; at: Date } | { kind: 'failed' };

const FIELD_LABELS: Record<string, string> = Object.fromEntries(
  SECTIONS.flatMap((sec) => sec.fields.map((f) => [f.path, f.label] as const)),
);
const fieldLabel = (path: string) => FIELD_LABELS[path] ?? path;
const fieldId = (path: string) => `f-${path.replace(/\./g, '-')}`;

/**
 * The guided editor for one client draft: one section per step, a final
 * review step, and a sticky action bar. The whole merged profile is what
 * every save sends; Skip only moves on.
 */
export function ClientEditor({ initial: initialDraft, paused }: { initial: ClientDraft; paused: boolean }) {
  const { api, config } = usePortal();
  const navigate = useNavigate();
  const [draft, setDraft] = useState(initialDraft);
  // The WHOLE working profile. Every save sends all of it, never one section.
  const [details, setDetails] = useState<ClientDetails>(initialDraft.details ?? {});
  const [index, setIndex] = useState(0);
  const [busy, setBusy] = useState(false);
  const [saveState, setSaveState] = useState<SaveState>({ kind: 'idle' });
  const [error, setError] = useState<unknown>(null);
  const [problems, setProblems] = useState<{ path: string; message: string }[]>([]);
  // Required paths the server named after a refused submit: shown on the fields.
  const [flagged, setFlagged] = useState<string[]>([]);
  const focusPath = useRef<string | null>(null);
  const [focusTick, setFocusTick] = useState(0);
  const [dialog, setDialog] = useState<'submit' | 'discard' | null>(null);
  const [justSubmitted, setJustSubmitted] = useState(false);
  const topRef = useRef<HTMLDivElement>(null);
  const stepRefs = useRef<(HTMLButtonElement | null)[]>([]);

  const editable = draft.editable && !paused;
  const limit = config?.clients?.draftLimit ?? null;
  const reviewIndex = SECTIONS.length;
  const onReview = index === reviewIndex;
  const section = SECTIONS[index];
  const dirty = useMemo(
    () => stable(normalizeDetails(details).details) !== stable(normalizeDetails(draft.details ?? {}).details),
    [details, draft.details],
  );

  // After a step change: keep the step button in view, then focus the field to fix.
  useEffect(() => {
    stepRefs.current[index]?.scrollIntoView?.({ block: 'nearest', inline: 'center' });
  }, [index]);
  useEffect(() => {
    const path = focusPath.current;
    if (!path) return;
    focusPath.current = null;
    const el = document.getElementById(fieldId(path));
    if (el) {
      el.focus({ preventScroll: true });
      el.scrollIntoView?.({ block: 'center' });
    }
  }, [focusTick, index]);

  function goTo(i: number, focus?: string) {
    setIndex(i);
    if (focus) {
      focusPath.current = focus;
      setFocusTick((t) => t + 1);
    }
    else topRef.current?.scrollIntoView?.({ block: 'start' });
  }

  async function save(): Promise<ClientDraft | null> {
    const { details: body, errors } = normalizeDetails(details);
    setProblems(errors);
    if (errors.length > 0) {
      const at = SECTIONS.findIndex((x) => x.key === sectionOf(errors[0].path));
      if (at >= 0) goTo(at);
      setSaveState({ kind: 'failed' });
      return null;
    }
    setBusy(true);
    setSaveState({ kind: 'saving' });
    setError(null);
    try {
      // Complete merged profile; the server replaces its copy with this.
      const next = await api.updateClient(draft.id, body);
      setDraft(next);
      setDetails(next.details ?? {});
      setSaveState({ kind: 'saved', at: new Date() });
      return next;
    } catch (e) {
      setError(e);
      setSaveState({ kind: 'failed' });
      return null;
    } finally {
      setBusy(false);
    }
  }

  async function saveAndNext() {
    const ok = await save();
    if (ok) goTo(Math.min(index + 1, reviewIndex));
  }

  /** Skip only moves on. It never clears, saves or edits anything. */
  function skip() {
    goTo(Math.min(index + 1, reviewIndex));
  }

  async function submit() {
    setDialog(null);
    setBusy(true);
    setError(null);
    try {
      const next = await api.submitClient(draft.id);
      setDraft(next);
      setDetails(next.details ?? {});
      setJustSubmitted(true);
      window.scrollTo?.({ top: 0 });
    } catch (e) {
      setError(e);
      if (e instanceof ApiError && e.code === 'CLIENT_PROFILE_INCOMPLETE') {
        const missing = e.missingFields ?? [];
        setFlagged(missing);
        const first = missing[0];
        const at = first ? SECTIONS.findIndex((x) => x.key === sectionOf(first)) : -1;
        if (at >= 0) goTo(at, first);
        try {
          setDraft(await api.getClient(draft.id));
        } catch {
          /* the error above is already shown */
        }
      } else if (e instanceof ApiError && e.code === 'CLIENT_DRAFT_LOCKED') {
        try {
          setDraft(await api.getClient(draft.id));
        } catch {
          /* keep the locked message */
        }
      }
      // CLIENT_PHONE_UNAVAILABLE: the draft stays a draft; Discard is offered.
    } finally {
      setBusy(false);
    }
  }

  async function discard() {
    setDialog(null);
    setBusy(true);
    setError(null);
    try {
      await api.deleteClient(draft.id);
      navigate('/clients', { replace: true });
    } catch (e) {
      setError(e);
      setBusy(false);
    }
  }

  const statusText = pickLabel(draft.statusLabel ?? config?.clientStatusLabels?.[draft.status], draft.status);
  const canSubmit = editable && draft.missingRequired.length === 0 && !dirty && !busy;
  const total = SECTIONS.length + 1;
  const stepTitle = onReview ? 'Review and submit' : section.title;
  const sectionDone = (key: string) => {
    const def = SECTIONS.find((x) => x.key === key)!;
    const stillRequired = def.fields.some((f) => draft.missingRequired.includes(f.path));
    return !stillRequired && def.fields.some((f) => isAnswered(details, f.path));
  };

  return (
    <>
      <div ref={topRef} />
      <p className="hint back-link">
        <Link to="/clients">← All clients</Link>
      </p>
      <header className="client-head">
        <span className="avatar big" aria-hidden="true">{initial(draft.displayName)}</span>
        <div className="client-head-text">
          <h1>{draft.displayName}</h1>
          <p className="hint">{draft.phoneMasked}</p>
          <p className="client-status-line">
            <StatusBadge tone={clientTone(draft.status)}>{statusText}</StatusBadge>
            {draft.expiresOn && isOpen(draft) && (
              <span className="hint">
                {draft.status === 'DRAFT' ? 'Open until' : 'Waiting until'} {draft.expiresOn}
              </span>
            )}
            {draft.status === 'ACCEPTED' && draft.acceptedOn && <span className="hint">Accepted {draft.acceptedOn}</span>}
          </p>
        </div>
      </header>
      {draft.status === 'ACCEPTED' && draft.referralId && (
        <p>
          <Link to="/referrals">See them in People who joined</Link>
        </p>
      )}
      {justSubmitted && draft.status === 'WAITING_FOR_CLIENT' && (
        <p className="notice success-notice" role="status">
          Submitted. Their invitation has been sent, and this profile is now locked.
        </p>
      )}
      {paused && <p className="notice">Your account is paused. You can look, but not change anything.</p>}
      {error != null && (
        <p className="error error-box" role="alert">
          {clientErrorMessage(error, limit)}
          {error instanceof ApiError && error.code === 'CLIENT_PROFILE_INCOMPLETE' && error.missingFields?.length
            ? ` Please fill in: ${error.missingFields.map(fieldLabel).join(', ')}.`
            : ''}
        </p>
      )}

      {draft.details === null && <p className="hint">Their details are no longer kept on this screen.</p>}

      {draft.details !== null && !editable && <ReadOnlyProfile details={draft.details} />}

      {editable && (
        <div className="editor">
          <div className="stepper-wrap">
            <div className="progress-head">
              <span className="progress-title">
                Step {index + 1} of {total} · {stepTitle}
              </span>
              <span className="hint" aria-label="Required fields left">
                {missingText(draft.missingRequired)}
              </span>
            </div>
            <div
              className="progress"
              role="progressbar"
              aria-label="Profile progress"
              aria-valuemin={1}
              aria-valuemax={total}
              aria-valuenow={index + 1}
            >
              <span style={{ width: `${((index + 1) / total) * 100}%` }} />
            </div>
            <nav aria-label="Sections" className="steps">
              {SECTIONS.map((x, i) => (
                <button
                  key={x.key}
                  ref={(el) => {
                    stepRefs.current[i] = el;
                  }}
                  type="button"
                  className="step"
                  data-done={sectionDone(x.key) || undefined}
                  aria-current={i === index ? 'step' : undefined}
                  onClick={() => goTo(i)}
                >
                  <span className="step-num" aria-hidden="true">
                    {sectionDone(x.key) ? <Icon name="check" size={13} /> : i + 1}
                  </span>
                  {x.title}
                </button>
              ))}
              <button
                ref={(el) => {
                  stepRefs.current[reviewIndex] = el;
                }}
                type="button"
                className="step"
                aria-current={onReview ? 'step' : undefined}
                onClick={() => goTo(reviewIndex)}
              >
                <span className="step-num" aria-hidden="true">{total}</span>
                Review
              </button>
            </nav>
          </div>

          <div className="step-panel">
            {!onReview && (
              <div className="card form-card">
                <h2>{section.title}</h2>
                <div className="field-grid">
                  {section.fields.map((f) => (
                    <FieldInput
                      key={f.path}
                      field={f}
                      details={details}
                      required={draft.missingRequired.includes(f.path)}
                      error={flagged.includes(f.path) && !isAnswered(details, f.path) ? 'Please fill this in.' : null}
                      onChange={(v) => {
                        setFlagged((cur) => cur.filter((x) => x !== f.path));
                        setDetails((d) => setAnswer(d, f.path, v));
                      }}
                    />
                  ))}
                </div>
                {section.siblings && (
                  <Siblings
                    rows={(getPath(details, 'familyDetails.siblings') as SiblingRow[] | undefined) ?? []}
                    problems={problems}
                    onChange={(rows) => setDetails((d) => setPath(d, 'familyDetails.siblings', rows))}
                  />
                )}
                {problems.length > 0 && (
                  <p className="error" role="alert">
                    {problems.map((p) => p.message).join(' ')}
                  </p>
                )}
              </div>
            )}

            {onReview && (
              <ReviewStep
                details={details}
                missing={draft.missingRequired}
                dirty={dirty}
                onEdit={goTo}
                onDiscard={() => setDialog('discard')}
                busy={busy}
              />
            )}
          </div>

          <div className="action-bar">
            <p className={`save-status${saveState.kind === 'failed' ? ' failed' : ''}`} role="status" aria-live="polite">
              {saveState.kind === 'saving' && 'Saving…'}
              {saveState.kind === 'failed' && 'Not saved. Your answers are still here.'}
              {saveState.kind !== 'saving' && saveState.kind !== 'failed' && dirty && 'You have unsaved changes'}
              {saveState.kind === 'saved' &&
                !dirty &&
                `Draft saved at ${saveState.at.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`}
            </p>
            <div className="action-row">
              {onReview ? (
                <>
                  <button type="button" className="primary-action" disabled={!canSubmit} onClick={() => setDialog('submit')}>
                    Submit to client
                  </button>
                  <button type="button" className="secondary" onClick={() => goTo(index - 1)} disabled={busy}>
                    Back
                  </button>
                  <button type="button" className="secondary" onClick={() => void save()} disabled={busy || !dirty}>
                    Save
                  </button>
                </>
              ) : (
                <>
                  <button type="button" className="primary-action" onClick={() => void saveAndNext()} disabled={busy}>
                    Save and continue
                  </button>
                  <button type="button" className="secondary" onClick={() => goTo(index - 1)} disabled={busy || index === 0}>
                    Back
                  </button>
                  <button type="button" className="secondary" onClick={skip} disabled={busy}>
                    Skip
                  </button>
                  <button type="button" className="secondary" onClick={() => void save()} disabled={busy}>
                    Save
                  </button>
                </>
              )}
            </div>
          </div>
        </div>
      )}

      {dialog === 'submit' && (
        <ConfirmDialog
          title="Submit to client?"
          confirmLabel="Yes, submit"
          cancelLabel="Cancel"
          busy={busy}
          onConfirm={() => void submit()}
          onCancel={() => setDialog(null)}
        >
          <p>
            This sends {draft.displayName}&rsquo;s profile to them as an invitation. Once submitted you can't change it, and
            you can't withdraw it.
          </p>
        </ConfirmDialog>
      )}
      {dialog === 'discard' && (
        <ConfirmDialog
          title="Discard this client?"
          confirmLabel="Yes, discard"
          cancelLabel="Keep"
          busy={busy}
          onConfirm={() => void discard()}
          onCancel={() => setDialog(null)}
        >
          <p>The draft and everything you entered for {draft.displayName} will be deleted.</p>
        </ConfirmDialog>
      )}
    </>
  );
}

// ─── Review ──────────────────────────────────────────────────────────

/** What to show for one answer: master-data fields show the server's label, not the code. */
function shownValue(details: ClientDetails, f: FieldDef): string {
  const label = f.kind === 'ref' ? getPath(details, f.path.replace(/Code$/, '')) : undefined;
  return String(label ?? getPath(details, f.path));
}

function siblingText(r: SiblingRow): string {
  const relation = r.relation === 'SISTER' ? 'Sister' : r.relation === 'BROTHER' ? 'Brother' : '';
  return [relation, r.name, r.age]
    .filter((x) => x !== undefined && x !== '')
    .join(' · ');
}

function ReviewStep({
  details,
  missing,
  dirty,
  onEdit,
  onDiscard,
  busy,
}: {
  details: ClientDetails;
  missing: string[];
  dirty: boolean;
  onEdit: (sectionIndex: number, focusPath?: string) => void;
  onDiscard: () => void;
  busy: boolean;
}) {
  const siblings = (getPath(details, 'familyDetails.siblings') as SiblingRow[] | undefined) ?? [];
  return (
    <>
      <div className="card form-card">
        <h2>Review and submit</h2>
        {missing.length === 0 ? (
          <p className="notice success-notice">All required details are filled in.</p>
        ) : (
          <div className="notice warn-notice">
            <p>
              <strong>{missingText(missing)}.</strong> Fill these in to submit:
            </p>
            <ul className="missing-list">
              {missing.map((path) => (
                <li key={path}>
                  <button
                    type="button"
                    className="link"
                    onClick={() => onEdit(SECTIONS.findIndex((x) => x.key === sectionOf(path)), path)}
                  >
                    {fieldLabel(path)}
                  </button>
                </li>
              ))}
            </ul>
          </div>
        )}
        {dirty && <p className="hint">Save your changes before submitting.</p>}
      </div>
      {SECTIONS.map((sec, i) => {
        const answered = sec.fields.filter((f) => isAnswered(details, f.path));
        const showSiblings = sec.siblings && siblings.length > 0;
        return (
          <section key={sec.key} className="card review-section" aria-label={`${sec.title} summary`}>
            <div className="review-head">
              <h3>{sec.title}</h3>
              <button type="button" className="link" aria-label={`Edit ${sec.title}`} onClick={() => onEdit(i)}>
                <Icon name="edit" size={16} /> Edit
              </button>
            </div>
            {answered.length === 0 && !showSiblings ? (
              <p className="hint">Not answered</p>
            ) : (
              <dl className="data-facts">
                {answered.map((f) => (
                  <div key={f.path}>
                    <dt>{f.label}</dt>
                    <dd>{shownValue(details, f)}</dd>
                  </div>
                ))}
                {showSiblings && (
                  <div className="wide">
                    <dt>Siblings</dt>
                    <dd>{siblings.map(siblingText).join('; ')}</dd>
                  </div>
                )}
              </dl>
            )}
          </section>
        );
      })}
      <div className="danger-zone">
        <button type="button" className="secondary danger" onClick={onDiscard} disabled={busy}>
          Discard
        </button>
        <span className="hint">Deletes this draft.</span>
      </div>
    </>
  );
}

// ─── Inputs ──────────────────────────────────────────────────────────

const today = () => new Date().toISOString().slice(0, 10);

function FieldInput({
  field,
  details,
  required,
  error,
  onChange,
}: {
  field: FieldDef;
  details: ClientDetails;
  required: boolean;
  error?: string | null;
  onChange: (v: string) => void;
}) {
  const id = fieldId(field.path);
  const value = (getPath(details, field.path) as string | undefined) ?? '';
  const isName = field.path === 'basicDetails.firstName' || field.path === 'basicDetails.lastName';
  return (
    <FormField
      id={id}
      label={field.label}
      required={required}
      error={error}
      className={field.kind === 'longtext' ? 'wide' : undefined}
    >
      {(p) => {
        if (field.kind === 'ref') return <RefSelect {...p} field={field} details={details} value={value} onChange={onChange} />;
        if (field.kind === 'choice')
          return (
            <select {...p} value={value} onChange={(e) => onChange(e.target.value)}>
              <option value="">Not answered</option>
              {field.options?.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          );
        if (field.kind === 'longtext')
          return (
            <>
              <textarea {...p} rows={4} value={value} maxLength={field.maxLength} onChange={(e) => onChange(e.target.value)} />
              {field.maxLength && (
                <p className="hint counter" aria-hidden="true">
                  {value.length} / {field.maxLength}
                </p>
              )}
            </>
          );
        return (
          <input
            {...p}
            type={field.kind === 'date' ? 'date' : 'text'}
            max={field.kind === 'date' ? today() : undefined}
            autoComplete="off"
            autoCapitalize={isName ? 'words' : 'sentences'}
            enterKeyHint="next"
            value={value}
            maxLength={field.maxLength}
            onChange={(e) => onChange(e.target.value)}
          />
        );
      }}
    </FormField>
  );
}

const REF_PARENT: Record<string, string | null> = {
  religion: null,
  community: 'religionDetails.religionCode',
  country: null,
  state: 'locationDetails.countryCode',
  city: 'locationDetails.stateCode',
};

/** A master-data dropdown whose options depend on its parent's chosen code. */
function RefSelect({
  field,
  details,
  value,
  onChange,
  ...aria
}: {
  field: FieldDef;
  details: ClientDetails;
  value: string;
  onChange: (v: string) => void;
  id: string;
}) {
  const { api } = usePortal();
  const kind = field.ref!;
  const parentPath = REF_PARENT[kind];
  const parent = parentPath ? ((getPath(details, parentPath) as string | undefined) ?? '') : null;
  const load = useCallback((): Promise<RefItem[]> => {
    switch (kind) {
      case 'religion':
        return api.getReligions();
      case 'country':
        return api.getCountries();
      case 'community':
        return parent ? api.getCommunities(parent) : Promise.resolve([]);
      case 'state':
        return parent ? api.getStates(parent) : Promise.resolve([]);
      default:
        return parent ? api.getCities(parent) : Promise.resolve([]);
    }
  }, [api, kind, parent]);
  const options = useAsync(load);
  const waiting = parentPath !== null && !parent;
  // A saved code the list does not (yet) contain is still shown, not lost.
  const items = options.data ?? [];
  const known = items.some((i) => i.code === value);
  return (
    <>
      <select {...aria} value={value} disabled={waiting || options.loading} onChange={(e) => onChange(e.target.value)}>
        <option value="">{waiting ? 'Choose the one above first' : options.loading ? 'Loading…' : 'Not answered'}</option>
        {value && !known && <option value={value}>{value}</option>}
        {items.map((i) => (
          <option key={i.code} value={i.code}>
            {i.label}
          </option>
        ))}
      </select>
      {options.error != null && <ErrorText error={options.error} onRetry={options.reload} />}
    </>
  );
}

function Siblings({
  rows,
  problems,
  onChange,
}: {
  rows: SiblingRow[];
  problems: { path: string; message: string }[];
  onChange: (rows: SiblingRow[]) => void;
}) {
  const set = (i: number, patch: Partial<SiblingRow>) =>
    onChange(rows.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  const bad = (i: number, key: string) => problems.some((p) => p.path === `familyDetails.siblings[${i}].${key}`);
  return (
    <fieldset className="siblings">
      <legend>Siblings</legend>
      {rows.map((r, i) => (
        <div key={i} className="sibling-row">
          <div className="sibling-head">
            <strong>Sibling {i + 1}</strong>
            <button
              type="button"
              className="link"
              aria-label={`Remove sibling ${i + 1}`}
              onClick={() => onChange(rows.filter((_, j) => j !== i))}
            >
              Remove
            </button>
          </div>
          <div className="field-grid">
            <div className="field">
              <span className="sub-label" aria-hidden="true">
                Relation <span className="req">(required)</span>
              </span>
              <select
                aria-label={`Sibling ${i + 1} relation`}
                aria-invalid={bad(i, 'relation') || undefined}
                value={r.relation ?? ''}
                onChange={(e) => set(i, { relation: e.target.value })}
              >
                <option value="">Brother or sister?</option>
                <option value="BROTHER">Brother</option>
                <option value="SISTER">Sister</option>
              </select>
              {bad(i, 'relation') && <p className="error field-error">Choose brother or sister.</p>}
            </div>
            <div className="field">
              <span className="sub-label" aria-hidden="true">Name</span>
              <input
                aria-label={`Sibling ${i + 1} name`}
                autoCapitalize="words"
                autoComplete="off"
                maxLength={50}
                value={r.name ?? ''}
                onChange={(e) => set(i, { name: e.target.value })}
              />
            </div>
            <div className="field">
              <span className="sub-label" aria-hidden="true">Age</span>
              <input
                aria-label={`Sibling ${i + 1} age`}
                inputMode="numeric"
                autoComplete="off"
                aria-invalid={bad(i, 'age') || undefined}
                value={r.age === undefined ? '' : String(r.age)}
                onChange={(e) => set(i, { age: e.target.value })}
              />
              {bad(i, 'age') && <p className="error field-error">Whole number from 0 to 120.</p>}
            </div>
          </div>
        </div>
      ))}
      {rows.length < 10 && (
        <button type="button" className="secondary" onClick={() => onChange([...rows, {}])}>
          Add a sibling
        </button>
      )}
    </fieldset>
  );
}

function ReadOnlyProfile({ details }: { details: ClientDetails }) {
  const groups = SECTIONS.map((s) => ({
    title: s.title,
    rows: s.fields
      .filter((f) => isAnswered(details, f.path))
      .map((f) => [f.label, shownValue(details, f)] as [string, string]),
  })).filter((g) => g.rows.length > 0);
  if (groups.length === 0) return <p className="hint">Nothing was filled in.</p>;
  return (
    <div className="profile-grid">
      {groups.map((g) => (
        <section key={g.title} className="card review-section" aria-label={g.title}>
          <h3>{g.title}</h3>
          <dl className="data-facts">
            {g.rows.map(([k, v]) => (
              <div key={k}>
                <dt>{k}</dt>
                <dd>{v}</dd>
              </div>
            ))}
          </dl>
        </section>
      ))}
    </div>
  );
}
