import { Global, Module } from '@nestjs/common';
import { LocationController } from './controllers/location.controller';
import { LocationService } from './services/location.service';

/**
 * Location reference data: the public read API, and the server-side authority
 * that profile and partner-preference writes validate against.
 *
 * @Global because LocationService holds the whole dataset in memory (see the
 * service) and the point of that is one copy per process. Left non-global,
 * every module that validates a location would import this module and Nest
 * would still share the single provider instance — but making it explicit
 * stops a future `providers: [LocationService]` in another module from
 * quietly creating a second copy of the entire dataset.
 *
 * PrismaService is already global, so nothing needs importing here.
 */
@Global()
@Module({
  controllers: [LocationController],
  providers: [LocationService],
  exports: [LocationService],
})
export class ReferenceDataModule {}
