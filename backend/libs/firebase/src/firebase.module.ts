import { Global, Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { FirebaseService } from './firebase.service';

@Global()
@Module({
  imports: [AppConfigModule],
  providers: [FirebaseService],
  exports: [FirebaseService],
})
export class FirebaseModule {}
