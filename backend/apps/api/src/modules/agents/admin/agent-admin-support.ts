/**
 * Shared rules for the admin services (docs/agent-program/agent-admin-api.openapi.yaml).
 *
 * - **Who:** `AdminActor` is the staff member behind the request. The
 *   controller (not built yet) fills `stepUpFresh` from Shaaz's
 *   `hasFreshStepUp(admin)`.
 * - **Permission** is checked through the `AgentPermissionPort` INSIDE the
 *   transaction, before anything is read or written. A sensitive permission
 *   (`payout.execute`, `agent.pii.reveal`) also needs a fresh step-up, checked
 *   right after the permission, so a caller without the key never learns about
 *   the step-up.
 * - **Reason:** every mutation takes one, 3 to 500 characters.
 * - **Masked output:** a view built here never holds a sealed value, a full
 *   phone number, a full PAN or full bank/UPI details.
 */
import { AgentMoneyError } from '../errors/agent-money-error';
import type { AgentPermissionPort } from '../ports/agent-platform-ports';
import type { AgentTx } from '../ports/agent-unit-of-work.port';
import type {
  AgentRecord,
  ReferralCodeRecord,
} from '../ports/agent-data-ports';
import { maskPhone } from '../referral/agent-referral-view';

export interface AdminActor {
  /** `users.id` of the staff member. */
  userId: string;
  /** An authenticator check within the step-up window (`hasFreshStepUp`). */
  stepUpFresh: boolean;
}

/** The permission keys used by the admin services, as in the contract. */
export const PERM = {
  agentView: 'agent.view',
  agentApprove: 'agent.approve',
  agentManage: 'agent.manage',
  agentPayoutDetailsVerify: 'agent.payout_details.verify',
  agentPiiReveal: 'agent.pii.reveal',
  attributionView: 'attribution.view',
  attributionOverride: 'attribution.override',
  commissionView: 'commission.view',
  commissionApprove: 'commission.approve',
  commissionCancel: 'commission.cancel',
  commissionOverride: 'commission.override',
  payoutView: 'payout.view',
  payoutExecute: 'payout.execute',
} as const;

export type PermissionKey = (typeof PERM)[keyof typeof PERM];

/** Permissions that also need a fresh step-up. */
const SENSITIVE: ReadonlySet<PermissionKey> = new Set([
  PERM.payoutExecute,
  PERM.agentPiiReveal,
]);

/** 'agent.payout_details.verify' -> { module: 'agent', action: 'payout_details.verify' } */
export function splitPermission(key: string): {
  module: string;
  action: string;
} {
  const dot = key.indexOf('.');
  return { module: key.slice(0, dot), action: key.slice(dot + 1) };
}

export async function requirePermission(
  permission: AgentPermissionPort,
  actor: AdminActor,
  key: PermissionKey,
  tx: AgentTx,
): Promise<void> {
  await permission.assert(actor.userId, splitPermission(key), tx);
  if (SENSITIVE.has(key) && !actor.stepUpFresh) {
    throw new AgentMoneyError('ADMIN_STEP_UP_REQUIRED');
  }
}

/** A reason is 3 to 500 characters once trimmed. Returns the trimmed text. */
export function requireReason(value: unknown): string {
  const text = typeof value === 'string' ? value.trim() : '';
  if (text.length < 3 || text.length > 500) {
    throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['reason'] });
  }
  return text;
}

export function requireId(name: string, value: unknown): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AgentMoneyError('VALIDATION_FAILED', { fields: [name] });
  }
  return value;
}

// --- cursors: opaque (createdAt, id) positions --------------------------------

export function encodeCursor(position: { at: Date; id: string }): string {
  return Buffer.from(`${position.at.toISOString()}|${position.id}`).toString(
    'base64url',
  );
}

export function decodeCursor(
  cursor: string | undefined,
): { at: Date; id: string } | undefined {
  if (cursor === undefined) return undefined;
  const text = Buffer.from(cursor, 'base64url').toString('utf8');
  const bar = text.indexOf('|');
  const at = new Date(bar < 0 ? NaN : text.slice(0, bar));
  const id = bar < 0 ? '' : text.slice(bar + 1);
  if (Number.isNaN(at.getTime()) || id === '') {
    throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['cursor'] });
  }
  return { at, id };
}

/** limit 1 to 100, default 25 (the contract). */
export function pageLimit(limit: number | undefined): number {
  if (limit === undefined) return 25;
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
    throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['limit'] });
  }
  return limit;
}

// --- masked views -----------------------------------------------------------

export interface AdminAgentListItem {
  id: string;
  name: string;
  city: string;
  state: string;
  phoneMasked: string;
  status: AgentRecord['status'];
  panLast4: string | null;
  panVerified: boolean;
  payoutDetailsSet: boolean;
  createdAt: string;
}

export function toAgentListItem(agent: AgentRecord): AdminAgentListItem {
  return {
    id: agent.id,
    name: agent.name,
    city: agent.city,
    state: agent.state,
    phoneMasked: maskPhone(agent.phoneE164),
    status: agent.status,
    panLast4: agent.panLast4,
    panVerified: agent.panVerifiedAt !== null,
    payoutDetailsSet: agent.payoutDetailsSet,
    createdAt: agent.createdAt.toISOString(),
  };
}

export interface AdminReferralCode {
  id: string;
  code: string;
  isPrimary: boolean;
  isActive: boolean;
  createdAt: string;
}

export const toReferralCode = (
  code: ReferralCodeRecord,
): AdminReferralCode => ({
  id: code.id,
  code: code.code,
  isPrimary: code.isPrimary,
  isActive: code.isActive,
  createdAt: code.createdAt.toISOString(),
});

/** The statuses an admin may still act on for payout details and PAN. */
export const PAYOUT_RELATED_STATUSES: ReadonlySet<string> = new Set([
  'ACTIVE',
  'SUSPENDED',
  'TERMINATED',
]);
