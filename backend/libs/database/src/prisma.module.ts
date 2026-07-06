import { Global, Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { PrismaService } from './prisma.service';
import { DatabaseHealthService } from './database.health';

@Global()
@Module({
  imports: [AppConfigModule],
  providers: [PrismaService, DatabaseHealthService],
  exports: [PrismaService, DatabaseHealthService],
})
export class PrismaModule {}
