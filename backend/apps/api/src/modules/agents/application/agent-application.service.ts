/**
 * Applying to become an agent (POST /agent/application).
 *
 * Needs an APPLICANT session, or a REJECTED agent's session when re-applying
 * is allowed. Creates the agent as PENDING_APPROVAL (or resubmits a rejected
 * one) and returns an AgentSession for it. The phone is never taken from the
 * request: it is the phone the applicant verified at sign-in, remembered
 * sealed by `AgentApplicantRepository`.
 *
 * Not wired into any module or controller yet. All changes run in
 * `AgentUnitOfWork.run`; the audit entry passes the same `tx`.
 *
 * PROPOSED HTTP MAPPING (to be confirmed; the contract lists only 409
 * APPLICATION_EXISTS for this endpoint). `AgentServiceError.code` is the
 * left-hand column.
 *
 * | code                     | when                                         | HTTP | contract `code`      |
 * |--------------------------|----------------------------------------------|------|----------------------|
 * | VALIDATION_FAILED        | name, city, state or pan is not acceptable   | 400  | VALIDATION_FAILED    |
 * | BAD_SCOPE                | token scope is neither AGENT nor APPLICANT   | 401  | UNAUTHORIZED         |
 * | SCOPE_MISMATCH           | AGENT token but no agent record              | 401  | UNAUTHORIZED         |
 * | UNAUTHORIZED             | applicant's verified phone expired or gone   | 401  | UNAUTHORIZED (verify again) |
 * | PHONE_ALREADY_REGISTERED | applicant token, but this phone now has an   | 409  | APPLICATION_EXISTS   |
 * |                          | agent record (applied from another device)   |      |                      |
 * | ALREADY_PENDING          | application is already under review          | 409  | APPLICATION_EXISTS   |
 * | ALREADY_AN_AGENT         | ACTIVE, SUSPENDED or TERMINATED              | 409  | APPLICATION_EXISTS   |
 * | REAPPLY_NOT_ALLOWED      | REJECTED, and re-applying is switched off    | 403  | AGENT_NOT_ACTIVE     |
 * | UNKNOWN_STATUS           | stored status the program does not know      | 500  | (internal error)     |
 *
 * For the three 409s and the 403 the error carries `agentStatus` so the
 * client can go to the right screen; the contract's Error schema documents
 * `agentStatus` only for AGENT_NOT_ACTIVE, so that is a small contract
 * addition to confirm.
 */
import { randomUUID } from 'node:crypto';
import { normalizePan } from '../agent/application-validators';
import { REJECTED_MAY_REAPPLY } from '../agent/agent-status';
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import { AgentSession, AgentSessionIssuer } from '../auth/agent-session-issuer';
import { decideApplicationSubmit } from '../auth/decide-application-submit';
import { AgentServiceError } from '../errors/agent-service-error';
import {
  AgentApplicantRepository,
  AgentConflictError,
  AgentRecord,
  AgentRefreshTokenRepository,
  AgentRepository,
} from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type { AgentAuditPort } from '../ports/agent-platform-ports';
import type { AgentSecretSealer } from '../ports/agent-secret-sealer.port';
import type { AgentUnitOfWork } from '../ports/agent-unit-of-work.port';

export interface AgentApplicationBody {
  name: string;
  city: string;
  state: string;
  /** Optional. Required, with payout details, before the first payout. */
  pan?: string;
}

export interface AgentApplicationDeps {
  agents: AgentRepository;
  refreshTokens: AgentRefreshTokenRepository;
  applicants: AgentApplicantRepository;
  sealer: AgentSecretSealer;
  uow: AgentUnitOfWork;
  audit: AgentAuditPort;
  clock: AgentClock;
  issuer: AgentSessionIssuer;
  /** Injectable so tests are deterministic. */
  newId?: () => string;
  /**
   * May a REJECTED agent apply again? Defaults to REJECTED_MAY_REAPPLY, the
   * one place that pending decision (Raja) lives.
   */
  rejectedMayReapply?: boolean;
}

interface CleanBody {
  name: string;
  city: string;
  state: string;
  pan: string | null;
}

export class AgentApplicationService {
  private readonly newId: () => string;

  constructor(private readonly deps: AgentApplicationDeps) {
    this.newId = deps.newId ?? randomUUID;
  }

  async submit(
    claims: AgentAccessClaims,
    body: AgentApplicationBody,
  ): Promise<AgentSession> {
    const clean = this.validate(body);
    const lifetimes = await this.deps.issuer.lifetimes();

    try {
      return await this.deps.uow.run(async (tx) => {
        const { agents, applicants, refreshTokens, sealer, audit, clock } =
          this.deps;
        const now = clock.now();

        // Who is calling, and what does the system already know about them?
        let existing: AgentRecord | null = null;
        let phoneAlreadyHasAgent = false;
        if (claims.scope === 'AGENT') {
          existing = await agents.findById(claims.sub, tx);
        } else if (claims.scope === 'APPLICANT') {
          phoneAlreadyHasAgent =
            (await agents.findByPhoneHash(claims.sub, tx)) !== null;
        }

        const decision = decideApplicationSubmit({
          tokenScope: claims.scope,
          existingAgentStatus: existing?.status ?? null,
          rejectedMayReapply:
            this.deps.rejectedMayReapply ?? REJECTED_MAY_REAPPLY,
          phoneAlreadyHasAgent,
        });
        if (!decision.allowed) {
          throw new AgentServiceError(decision.reason, {
            agentStatus: existing?.status,
          });
        }

        if (decision.action === 'RESUBMIT_PENDING') {
          // A rejected agent starts over: the old session family is revoked
          // and a new one is issued.
          // A different PAN has not been checked: its verification is cleared.
          const panChanged =
            clean.pan !== null &&
            (existing!.panSealed === null ||
              sealer.open(existing!.panSealed) !== clean.pan);
          const agent = await agents.update(
            existing!.id,
            {
              name: clean.name,
              city: clean.city,
              state: clean.state,
              status: 'PENDING_APPROVAL',
              rejectionReason: null,
              ...(clean.pan === null
                ? {}
                : {
                    panLast4: clean.pan.slice(-4),
                    panSealed: sealer.seal(clean.pan),
                    ...(panChanged ? { panVerifiedAt: null } : {}),
                  }),
            },
            tx,
          );
          await refreshTokens.revokeAllForAgent(agent.id, now, tx);
          await audit.record(
            {
              actorId: agent.id,
              action: 'AGENT_APPLICATION_RESUBMITTED',
              entity: 'agent',
              entityId: agent.id,
              metadata: { panProvided: clean.pan !== null },
            },
            tx,
          );
          return this.deps.issuer.issueAgent(agent, tx, lifetimes);
        }

        // CREATE_PENDING: the phone is the one the applicant verified.
        const applicant = await applicants.find(claims.sub, tx);
        if (
          applicant === null ||
          applicant.expiresAt.getTime() <= now.getTime()
        ) {
          throw new AgentServiceError('UNAUTHORIZED');
        }
        const agent = await agents.create(
          {
            id: this.newId(),
            phoneHash: claims.sub,
            phoneE164: sealer.open(applicant.phoneSealed),
            name: clean.name,
            city: clean.city,
            state: clean.state,
            panLast4: clean.pan === null ? null : clean.pan.slice(-4),
            panSealed: clean.pan === null ? null : sealer.seal(clean.pan),
            createdAt: now,
          },
          tx,
        );
        await applicants.delete(claims.sub, tx);
        await audit.record(
          {
            actorId: agent.id,
            action: 'AGENT_APPLICATION_SUBMITTED',
            entity: 'agent',
            entityId: agent.id,
            metadata: { panProvided: clean.pan !== null },
          },
          tx,
        );
        return this.deps.issuer.issueAgent(agent, tx, lifetimes);
      });
    } catch (error) {
      // Two applications for one phone at once: the database said no.
      if (
        error instanceof AgentConflictError &&
        error.reason === 'DUPLICATE_PHONE_HASH'
      ) {
        throw new AgentServiceError('PHONE_ALREADY_REGISTERED');
      }
      throw error;
    }
  }

  /** Trims and checks the body. Names the bad fields, never their values. */
  private validate(body: AgentApplicationBody): CleanBody {
    const invalid: string[] = [];
    const text = (value: unknown, field: string, min: number, max: number) => {
      const trimmed = typeof value === 'string' ? value.trim() : '';
      if (trimmed.length < min || trimmed.length > max) invalid.push(field);
      return trimmed;
    };
    const name = text(body?.name, 'name', 2, 100);
    const city = text(body?.city, 'city', 1, 80);
    const state = text(body?.state, 'state', 1, 80);

    let pan: string | null = null;
    if (body?.pan !== undefined) {
      pan = normalizePan(body.pan);
      if (pan === null) invalid.push('pan');
    }
    if (invalid.length > 0) {
      throw new AgentServiceError('VALIDATION_FAILED', { fields: invalid });
    }
    return { name, city, state, pan };
  }
}
