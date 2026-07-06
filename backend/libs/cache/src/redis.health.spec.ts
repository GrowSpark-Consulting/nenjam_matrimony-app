import { RedisHealthService } from './redis.health';
import { RedisService } from './redis.service';

describe('RedisHealthService', () => {
  function buildHealthService(
    pingImpl: () => Promise<string>,
  ): RedisHealthService {
    const redisService = {
      getClient: () => ({ ping: jest.fn(pingImpl) }),
    } as unknown as RedisService;
    return new RedisHealthService(redisService);
  }

  it('reports up with latency and the ping result on success', async () => {
    const service = buildHealthService(() => Promise.resolve('PONG'));

    const health = await service.check();

    expect(health.status).toBe('up');
    expect(health.ping).toBe('PONG');
    expect(health.latencyMs).toBeGreaterThanOrEqual(0);
    expect(health.error).toBeUndefined();
  });

  it('reports down with the error message when ping fails', async () => {
    const service = buildHealthService(() =>
      Promise.reject(new Error('connection closed')),
    );

    const health = await service.check();

    expect(health.status).toBe('down');
    expect(health.error).toBe('connection closed');
    expect(health.latencyMs).toBeUndefined();
  });
});
