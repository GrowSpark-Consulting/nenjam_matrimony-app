import { BadRequestException, ValidationPipe } from '@nestjs/common';
import { UpdatePrivacyDto } from '../dto/update-privacy.dto';

// The same options main.ts registers globally.
const pipe = new ValidationPipe({
  whitelist: true,
  forbidNonWhitelisted: true,
  transform: true,
});

function validate(body: Record<string, unknown>) {
  return pipe.transform(body, { type: 'body', metatype: UpdatePrivacyDto });
}

describe('UpdatePrivacyDto', () => {
  it('accepts the privacy toggles', async () => {
    await expect(
      validate({
        hideMyProfile: true,
        hidePhotosFromNonConnections: false,
        profileVisibleToPremiumOnly: true,
      }),
    ).resolves.toBeInstanceOf(UpdatePrivacyDto);
  });

  it('rejects a client-supplied isPremium — premium status cannot be forged', async () => {
    await expect(
      validate({ hideMyProfile: true, isPremium: true }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects non-boolean values', async () => {
    await expect(validate({ hideMyProfile: 'yes' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });
});
