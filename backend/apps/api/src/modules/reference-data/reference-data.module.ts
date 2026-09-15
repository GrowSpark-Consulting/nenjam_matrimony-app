import { Global, Module } from '@nestjs/common';
import { LocationController } from './controllers/location.controller';
import { LocationService } from './services/location.service';
import { ReligionController } from './controllers/religion.controller';
import { ReligionService } from './services/religion.service';

/**
 * Reference data: the public read APIs, and the server-side authority that
 * profile and partner-preference writes validate against.
 *
 * Two cascades live here and are deliberately kept apart —
 * Country -> State -> City, and Religion -> Community. They share a shape but
 * not a table, and nothing reads across them.
 *
 * @Global because these services memoise their lists in memory and the point
 * of that is one copy per process. Left non-global, every module that
 * validates a location or a community would import this module and Nest would
 * still share the single provider instance — but making it explicit stops a
 * future `providers: [LocationService]` in another module from quietly
 * creating a second copy.
 *
 * PrismaService is already global, so nothing needs importing here.
 */
@Global()
@Module({
  controllers: [LocationController, ReligionController],
  providers: [LocationService, ReligionService],
  exports: [LocationService, ReligionService],
})
export class ReferenceDataModule {}
