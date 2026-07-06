import { ElasticsearchHealthService } from './elasticsearch.health';
import { ElasticsearchService } from './elasticsearch.service';

describe('ElasticsearchHealthService', () => {
  function buildHealthService(
    pingImpl: () => Promise<unknown>,
  ): ElasticsearchHealthService {
    const elasticsearchService = {
      getClient: () => ({ ping: jest.fn(pingImpl) }),
    } as unknown as ElasticsearchService;
    return new ElasticsearchHealthService(elasticsearchService);
  }

  it('reports up with a latency measurement when ping succeeds', async () => {
    const service = buildHealthService(() => Promise.resolve({ body: true }));

    const health = await service.check();

    expect(health.status).toBe('up');
    expect(health.latencyMs).toBeGreaterThanOrEqual(0);
    expect(health.error).toBeUndefined();
  });

  it('reports down with the error message when ping fails', async () => {
    const service = buildHealthService(() =>
      Promise.reject(new Error('Connection Error')),
    );

    const health = await service.check();

    expect(health.status).toBe('down');
    expect(health.error).toBe('Connection Error');
    expect(health.latencyMs).toBeUndefined();
  });
});
