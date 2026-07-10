import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  UsePipes,
  ValidationPipe,
} from '@nestjs/common';
import { AuthService } from '../services/auth.service';
import { LoginDto } from '../dto/login.dto';
import { AuthTokensResponseDto } from '../dto/auth-tokens.response.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('firebase')
  @HttpCode(HttpStatus.OK)
  @UsePipes(new ValidationPipe({ whitelist: true, transform: true }))
  loginWithFirebase(
    @Body() { idToken }: LoginDto,
  ): Promise<AuthTokensResponseDto> {
    return this.authService.authenticateWithFirebase(idToken);
  }
}
