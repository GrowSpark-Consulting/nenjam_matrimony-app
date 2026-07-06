import { Injectable } from '@nestjs/common';
import { ElasticsearchService } from './elasticsearch.service';

export interface ElasticsearchHealth {
  status: 'up' | 'down';
  latencyMs?: number;
  error?: string;
}

@Injectable()
export class ElasticsearchHealthService {
  constructor(private readonly elasticsearchService: ElasticsearchService) {}

  async check(): Promise<ElasticsearchHealth> {
    const start = Date.now();

    try {
      await this.elasticsearchService.getClient().ping();
      return { status: 'up', latencyMs: Date.now() - start };
    } catch (error) {
      return {
        status: 'down',
        error:
          error instanceof Error
            ? error.message
            : 'Unknown Elasticsearch error',
      };
    }
  }
}
