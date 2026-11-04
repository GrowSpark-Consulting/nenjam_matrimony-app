/**
 * Ports for the agent's own money routes (GET /agent/commissions,
 * GET /agent/balance, GET /agent/payouts) and POST /agent/devices.
 */
import type { AgentTx } from './agent-unit-of-work.port';

/** What an agent is shown about a commission besides its own numbers. */
export interface CommissionDisplay {
  /** "Priya S." - never the full name. */
  referralDisplayName: string;
  planName: string;
}

export interface AgentCommissionDisplayPort {
  /**
   * Display fields per commission id, for the given commissions. A
   * commission whose member or plan can no longer be read is left out; the
   * caller decides what to show instead.
   */
  describe(
    commissions: ReadonlyArray<{
      id: string;
      paymentId: string;
      attributionId: string;
    }>,
    tx?: AgentTx,
  ): Promise<Map<string, CommissionDisplay>>;
}

export type AgentDevicePlatform = 'ANDROID' | 'IOS';

export interface AgentDeviceRepository {
  /**
   * Upsert on `fcmToken`: a token already held by another agent moves to
   * this one, and the device is active again.
   */
  register(
    device: {
      agentId: string;
      fcmToken: string;
      platform: AgentDevicePlatform;
    },
    tx?: AgentTx,
  ): Promise<void>;
}
