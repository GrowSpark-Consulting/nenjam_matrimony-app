import { DatabaseHealthService } from './database.health';
import { PrismaService } from './prisma.service';

describe('DatabaseHealthService', () => {
  function buildHealthService(
    queryRawImpl: () => Promise<unknown>,
  ): DatabaseHealthService {
    const prisma = {
      $queryRaw: jest.fn(queryRawImpl),
    } as unknown as PrismaService;
    return new DatabaseHealthService(prisma);
  }

  it('reports up with a latency measurement when the query succeeds', async () => {
    const service = buildHealthService(() =>
      Promise.resolve([{ '?column?': 1 }]),
    );

    const health = await service.check();

    expect(health.status).toBe('up');
    expect(health.latencyMs).toBeGreaterThanOrEqual(0);
    expect(health.error).toBeUndefined();
  });

  it('reports down with the error message when the query fails', async () => {
    const service = buildHealthService(() =>
      Promise.reject(new Error('connection terminated')),
    );

    const health = await service.check();

    expect(health.status).toBe('down');
    expect(health.error).toBe('connection terminated');
    expect(health.latencyMs).toBeUndefined();
  });
});
