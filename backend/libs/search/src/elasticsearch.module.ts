import { Global, Module } from '@nestjs/common';
import { Client } from '@elastic/elasticsearch';
import { AppConfigModule, AppConfigService } from '@app/config';
import { ELASTICSEARCH_CLIENT } from './elasticsearch.constants';
import { ElasticsearchService } from './elasticsearch.service';
import { ElasticsearchHealthService } from './elasticsearch.health';

@Global()
@Module({
  imports: [AppConfigModule],
  providers: [
    {
      provide: ELASTICSEARCH_CLIENT,
      inject: [AppConfigService],
      useFactory: (configService: AppConfigService) => {
        const { node, username, password } = configService.elasticsearch;

        return new Client({
          node,
          ...(username && password ? { auth: { username, password } } : {}),
          // Local dev clusters commonly run on a self-signed cert (curl
          // needs -k to reach them too) — only bypass verification here,
          // never in production.
          ...(configService.isDevelopment
            ? { ssl: { rejectUnauthorized: false } }
            : {}),
          requestTimeout: 5000,
          maxRetries: 0,
        });
      },
    },
    ElasticsearchService,
    ElasticsearchHealthService,
  ],
  exports: [
    ELASTICSEARCH_CLIENT,
    ElasticsearchService,
    ElasticsearchHealthService,
  ],
})
export class ElasticsearchModule {}
