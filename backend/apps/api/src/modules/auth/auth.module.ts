import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AppConfigModule, AppConfigService } from '@app/config';
import { AuthController } from './controllers/auth.controller';
import { AuthRepository } from './repositories/auth.repository';
import { AuthService } from './services/auth.service';
import { FirebaseTokenService } from './services/firebase-token.service';
import { TokenService } from './services/token.service';

@Module({
  imports: [
    JwtModule.registerAsync({
      imports: [AppConfigModule],
      inject: [AppConfigService],
      useFactory: (configService: AppConfigService) => ({
        secret: configService.jwt.secret,
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthRepository, AuthService, FirebaseTokenService, TokenService],
  exports: [AuthService, FirebaseTokenService, TokenService],
})
export class AuthModule {}
