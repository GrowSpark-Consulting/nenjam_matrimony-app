/**
 * The signed-in agent's own profile and payout details (GET /agent/me,
 * PATCH /agent/me/payout-details), plus the capability check every other
 * agent endpoint will use.
 *
 * Not wired into any module or controller yet. Output is masked: the phone,
 * the PAN and the payout details are never returned in full, and what is
 * stored is sealed. The payout-details change and its audit entry run in
 * `AgentUnitOfWork.run` and share its `tx`.
 */
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import { AgentServiceError } from '../errors/agent-service-error';
import type {
  AgentPayoutDetailsRepository,
  AgentPayoutMethod,
  AgentRecord,
  AgentRepository,
} from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type { AgentAuditPort } from '../ports/agent-platform-ports';
import {
  AGENT_SEAL_PURPOSES,
  type AgentSecretSealer,
} from '../ports/agent-secret-sealer.port';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';
import { AgentCapabilities, agentCapabilitiesFor } from './agent-status';
import {
  normalizeBankAccountNumber,
  normalizeIfsc,
  normalizeUpiId,
  maskUpiId,
} from './application-validators';
import { AgentProfile, AgentProfileBuilder } from './agent-profile-builder';

export interface AgentPayoutDetailsInput {
  upi?: { vpa: string };
  bank?: { accountHolderName: string; accountNumber: string; ifsc: string };
}

/** The contract's PayoutDetailsSummary: masked, never the full value. */
export interface AgentPayoutDetailsSummary {
  method: AgentPayoutMethod;
  display: string;
}

export interface AgentMeDeps {
  agents: AgentRepository;
  payoutDetails: AgentPayoutDetailsRepository;
  profiles: AgentProfileBuilder;
  sealer: AgentSecretSealer;
  uow: AgentUnitOfWork;
  audit: AgentAuditPort;
  clock: AgentClock;
}

type ApplicantAnswer = 'AGENT_NOT_FOUND' | 'UNAUTHORIZED';

export class AgentMeService {
  constructor(private readonly deps: AgentMeDeps) {}

  /** GET /agent/me. An applicant has no agent record yet: AGENT_NOT_FOUND. */
  async getProfile(claims: AgentAccessClaims): Promise<AgentProfile> {
    const agent = await this.assertCan(claims, 'viewStatus', {
      applicantAnswer: 'AGENT_NOT_FOUND',
    });
    return this.deps.profiles.build(agent);
  }

  /** What the caller's status allows (the table in `agent-status.ts`). */
  async capabilities(claims: AgentAccessClaims): Promise<AgentCapabilities> {
    const agent = await this.assertCan(claims, 'viewStatus', {
      applicantAnswer: 'AGENT_NOT_FOUND',
    });
    return agentCapabilitiesFor(agent.status);
  }

  /**
   * The check every agent endpoint starts with: the caller must be an agent
   * whose status allows `capability`. Returns the agent record. Refuses with
   * AGENT_NOT_ACTIVE (carrying the status) when the status does not allow it.
   */
  async assertCan(
    claims: AgentAccessClaims,
    capability: keyof AgentCapabilities,
    options: { applicantAnswer?: ApplicantAnswer; tx?: AgentTx } = {},
  ): Promise<AgentRecord> {
    if (claims.scope === 'APPLICANT') {
      throw new AgentServiceError(options.applicantAnswer ?? 'UNAUTHORIZED');
    }
    if (claims.scope !== 'AGENT') throw new AgentServiceError('UNAUTHORIZED');
    const agent = await this.deps.agents.findById(claims.sub, options.tx);
    if (agent === null) throw new AgentServiceError('AGENT_NOT_FOUND');
    if (!agentCapabilitiesFor(agent.status)[capability]) {
      throw new AgentServiceError('AGENT_NOT_ACTIVE', {
        agentStatus: agent.status,
      });
    }
    return agent;
  }

  /**
   * PATCH /agent/me/payout-details. ACTIVE agents only. Exactly one of `upi`
   * or `bank`. The details are stored sealed; verification is cleared and the
   * change time recorded, so the payout wait starts again.
   */
  async updatePayoutDetails(
    claims: AgentAccessClaims,
    input: AgentPayoutDetailsInput,
  ): Promise<AgentPayoutDetailsSummary> {
    // The status is judged before the body: a paused agent gets 403, not 400.
    await this.assertCan(claims, 'editPayoutDetails');
    const clean = this.validate(input);

    return this.deps.uow.run(async (tx) => {
      const { agents, payoutDetails, sealer, audit, clock } = this.deps;
      // Re-check inside the transaction: the status may have just changed.
      const agent = await this.assertCan(claims, 'editPayoutDetails', { tx });
      await payoutDetails.save(
        {
          agentId: agent.id,
          method: clean.method,
          detailsSealed: sealer.seal(
            AGENT_SEAL_PURPOSES.payoutDetails,
            clean.secret,
          ),
          display: clean.display,
          verifiedAt: null,
          changedAt: clock.now(),
        },
        tx,
      );
      await agents.update(agent.id, { payoutDetailsSet: true }, tx);
      await audit.record(
        {
          actorId: agent.id,
          action: 'AGENT_PAYOUT_DETAILS_CHANGED',
          entity: 'agent',
          entityId: agent.id,
          metadata: { method: clean.method },
        },
        tx,
      );
      return { method: clean.method, display: clean.display };
    });
  }

  /** Normalises the details. Names bad fields, never their values. */
  private validate(input: AgentPayoutDetailsInput): {
    method: AgentPayoutMethod;
    secret: string;
    display: string;
  } {
    const fail = (...fields: string[]): never => {
      throw new AgentServiceError('VALIDATION_FAILED', { fields });
    };
    const hasUpi = input?.upi !== undefined;
    const hasBank = input?.bank !== undefined;
    if (hasUpi === hasBank) return fail('upi', 'bank');

    if (hasUpi) {
      const vpa = normalizeUpiId(input.upi?.vpa);
      if (vpa === null) return fail('upi');
      return {
        method: 'UPI',
        secret: JSON.stringify({ vpa }),
        display: maskUpiId(vpa),
      };
    }

    const bank = input.bank;
    const holder =
      typeof bank?.accountHolderName === 'string'
        ? bank.accountHolderName.trim()
        : '';
    const account = normalizeBankAccountNumber(bank?.accountNumber);
    const ifsc = normalizeIfsc(bank?.ifsc);
    const invalid: string[] = [];
    if (holder.length < 1 || holder.length > 100)
      invalid.push('bank.accountHolderName');
    if (account === null) invalid.push('bank.accountNumber');
    if (ifsc === null) invalid.push('bank.ifsc');
    if (invalid.length > 0 || account === null || ifsc === null) {
      return fail(...invalid);
    }
    return {
      method: 'BANK',
      secret: JSON.stringify({
        accountHolderName: holder,
        accountNumber: account,
        ifsc,
      }),
      // Bank code and the last four digits only, as in the contract example.
      display: `${ifsc.slice(0, 4)} ****${account.slice(-4)}`,
    };
  }
}
