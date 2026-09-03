import { Module } from '@nestjs/common';
import { PrismaModule } from '@app/database';
import { FirebaseModule } from '@app/firebase';
import { AccountAvailabilityController } from './controllers/account-availability.controller';
import { DummyOtpSessionController } from './controllers/dummy-otp-session.controller';
import { DummyOtpSessionService } from './services/dummy-otp-session.service';

/// Carries the two unauthenticated signup endpoints — the account-availability
/// check and the dummy-OTP session exchange; the rest of the module is still a
/// stub.
@Module({
  imports: [FirebaseModule, PrismaModule],
  controllers: [AccountAvailabilityController, DummyOtpSessionController],
  providers: [DummyOtpSessionService],
})
export class UsersModule {}
