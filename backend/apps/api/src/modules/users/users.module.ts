import { Module } from '@nestjs/common';
import { FirebaseModule } from '@app/firebase';
import { AccountAvailabilityController } from './controllers/account-availability.controller';

/// Currently carries only the signup account-availability check; the rest of
/// the module is still a stub.
@Module({
  imports: [FirebaseModule],
  controllers: [AccountAvailabilityController],
})
export class UsersModule {}
