/** In-memory stand-ins for the money-route ports. Tests only. */
import type {
  AgentCommissionDisplayPort,
  AgentDevicePlatform,
  AgentDeviceRepository,
  CommissionDisplay,
} from '../ports/agent-money-read.port';

export class FakeAgentCommissionDisplay implements AgentCommissionDisplayPort {
  /** Keyed by commission id. */
  readonly shown = new Map<string, CommissionDisplay>();
  calls = 0;

  describe(
    commissions: ReadonlyArray<{ id: string }>,
  ): Promise<Map<string, CommissionDisplay>> {
    this.calls += 1;
    const result = new Map<string, CommissionDisplay>();
    for (const c of commissions) {
      const shown = this.shown.get(c.id);
      if (shown) result.set(c.id, { ...shown });
    }
    return Promise.resolve(result);
  }
}

export interface FakeAgentDevice {
  agentId: string;
  fcmToken: string;
  platform: AgentDevicePlatform;
  isActive: boolean;
}

export class FakeAgentDeviceRepository implements AgentDeviceRepository {
  /** Keyed by token: one row per token, as the unique index enforces. */
  readonly byToken = new Map<string, FakeAgentDevice>();

  register(device: {
    agentId: string;
    fcmToken: string;
    platform: AgentDevicePlatform;
  }): Promise<void> {
    this.byToken.set(device.fcmToken, { ...device, isActive: true });
    return Promise.resolve();
  }
}
