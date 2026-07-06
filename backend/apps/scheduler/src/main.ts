import { NestFactory } from '@nestjs/core';
import { SchedulerModule } from './scheduler.module';

async function bootstrap() {
  const app = await NestFactory.createApplicationContext(SchedulerModule);
  app.enableShutdownHooks();
  console.log('Scheduler service started');
}
void bootstrap();
