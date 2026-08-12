import {
  Inject,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import type { Client } from '@elastic/elasticsearch';
import { AppConfigService } from '@app/config';
import { ELASTICSEARCH_CLIENT } from './elasticsearch.constants';

@Injectable()
export class ElasticsearchService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(ElasticsearchService.name);

  constructor(
    @Inject(ELASTICSEARCH_CLIENT) private readonly client: Client,
    private readonly configService: AppConfigService,
  ) {}

  getClient(): Client {
    return this.client;
  }

  async onModuleInit(): Promise<void> {
    const start = Date.now();

    try {
      await this.client.ping();
    } catch (error) {
      this.handleStartupFailure(error);
      return;
    }

    const latencyMs = Date.now() - start;

    this.logger.log(
      [
        '=====================================',
        'ELASTICSEARCH',
        '',
        `Node        : ${this.redactedNode()}`,
        'Connection  : SUCCESS',
        `Latency     : ${latencyMs} ms`,
        '',
        '=====================================',
      ].join('\n'),
    );
  }

  // Elasticsearch is optional infrastructure in every environment, not just
  // development: no live feature depends on it today (search runs on
  // PostgresSearchStrategy — see apps/api's MatchesModule; no
  // ElasticsearchSearchStrategy exists yet). An absent or unreachable
  // cluster must never crash-loop the API, worker, or scheduler, so this no
  // longer branches on NODE_ENV. Revisit this once a real feature is built
  // on ElasticsearchService.getClient() and a genuine boot dependency
  // exists.
  private handleStartupFailure(error: unknown): void {
    const description = this.describeConnectionError(error);

    this.logger.warn(
      `Elasticsearch unavailable — continuing without it: ${description}`,
    );
  }

  async onModuleDestroy(): Promise<void> {
    await this.client.close();
  }

  // Elasticsearch client errors don't carry a stable numeric/POSIX code the
  // way pg or ioredis do — classification here is based on the error class
  // name and message content, verified empirically against a stopped server,
  // an invalid host, and a black-holed connection.
  private describeConnectionError(error: unknown): string {
    const err = error as
      | { name?: string; message?: string; meta?: { statusCode?: number } }
      | undefined;
    const node = this.redactedNode();

    if (err?.name === 'TimeoutError') {
      return `Connection to Elasticsearch at ${node} timed out.`;
    }
    if (err?.name === 'ConnectionError') {
      if (err.message?.includes('ENOTFOUND')) {
        return `Invalid Elasticsearch host in "${node}". DNS lookup failed.`;
      }
      return `Elasticsearch is unreachable at ${node}. Is it running?`;
    }
    if (
      err?.name === 'ResponseError' &&
      (err.meta?.statusCode === 401 || err.meta?.statusCode === 403)
    ) {
      return `Authentication failed connecting to Elasticsearch at ${node}.`;
    }
    return err?.message || 'Unknown Elasticsearch connection error.';
  }

  private redactedNode(): string {
    const node = this.configService.elasticsearch.node;
    try {
      const url = new URL(node);
      url.username = '';
      url.password = '';
      return url.toString();
    } catch {
      return node;
    }
  }
}
