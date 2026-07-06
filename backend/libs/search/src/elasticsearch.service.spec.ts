import { Logger } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { AppConfigService } from '@app/config';
import { ELASTICSEARCH_CLIENT } from './elasticsearch.constants';
import { ElasticsearchService } from './elasticsearch.service';

function buildMockClient() {
  return {
    ping: jest.fn(),
    close: jest.fn(),
  };
}

type MockClient = ReturnType<typeof buildMockClient>;

describe('ElasticsearchService', () => {
  async function buildService(
    client: MockClient,
    node = 'http://localhost:9200',
  ): Promise<ElasticsearchService> {
    const mockConfig = {
      elasticsearch: { node },
    } as unknown as AppConfigService;

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ElasticsearchService,
        { provide: ELASTICSEARCH_CLIENT, useValue: client },
        { provide: AppConfigService, useValue: mockConfig },
      ],
    }).compile();

    return module.get(ElasticsearchService);
  }

  it('pings successfully and logs a banner', async () => {
    const client = buildMockClient();
    client.ping.mockResolvedValue({ body: true });
    const service = await buildService(client);
    const logSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation();

    await service.onModuleInit();

    expect(client.ping).toHaveBeenCalled();
    const output = logSpy.mock.calls.map((call) => String(call[0])).join('\n');
    expect(output).toContain('ELASTICSEARCH');
    expect(output).toContain('Connection  : SUCCESS');

    logSpy.mockRestore();
  });

  it('redacts credentials embedded in the node URL from the log banner', async () => {
    const client = buildMockClient();
    client.ping.mockResolvedValue({ body: true });
    const service = await buildService(
      client,
      'http://user:secret-pw@localhost:9200',
    );
    const logSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation();

    await service.onModuleInit();

    const output = logSpy.mock.calls.map((call) => String(call[0])).join('\n');
    expect(output).not.toContain('secret-pw');

    logSpy.mockRestore();
  });

  it('classifies a stopped/unreachable server as a connection failure', async () => {
    const client = buildMockClient();
    const error = Object.assign(new Error('Connection Error'), {
      name: 'ConnectionError',
    });
    client.ping.mockRejectedValue(error);
    const service = await buildService(client);
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    await expect(service.onModuleInit()).rejects.toBe(error);
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('unreachable');

    errorSpy.mockRestore();
  });

  it('classifies an invalid host from the ConnectionError message', async () => {
    const client = buildMockClient();
    const error = Object.assign(new Error('getaddrinfo ENOTFOUND bogus-host'), {
      name: 'ConnectionError',
    });
    client.ping.mockRejectedValue(error);
    const service = await buildService(client, 'http://bogus-host:9200');
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    await expect(service.onModuleInit()).rejects.toBe(error);
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('Invalid Elasticsearch host');

    errorSpy.mockRestore();
  });

  it('classifies a TimeoutError distinctly from a connection failure', async () => {
    const client = buildMockClient();
    const error = Object.assign(new Error('Request timed out'), {
      name: 'TimeoutError',
    });
    client.ping.mockRejectedValue(error);
    const service = await buildService(client);
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    await expect(service.onModuleInit()).rejects.toBe(error);
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('timed out');

    errorSpy.mockRestore();
  });

  it('classifies a 401/403 ResponseError as an authentication failure', async () => {
    const client = buildMockClient();
    const error = Object.assign(new Error('Response Error'), {
      name: 'ResponseError',
      meta: { statusCode: 401 },
    });
    client.ping.mockRejectedValue(error);
    const service = await buildService(client);
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    await expect(service.onModuleInit()).rejects.toBe(error);
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('Authentication failed');

    errorSpy.mockRestore();
  });

  it('closes the client on module destroy', async () => {
    const client = buildMockClient();
    client.close.mockResolvedValue(undefined);
    const service = await buildService(client);

    await service.onModuleDestroy();

    expect(client.close).toHaveBeenCalled();
  });
});
