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
      useFactory: (configService: AppConfigService) =>
        new Client({
          node: configService.elasticsearch.node,
          requestTimeout: 5000,
          maxRetries: 0,
        }),
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
