import { BadRequestException, ValidationPipe } from '@nestjs/common';
import { UpdatePartnerPreferenceDto } from '../dto/partner-preference.dto';

/**
 * The whitelist is where the advanced preferences were being lost.
 *
 * The API runs `forbidNonWhitelisted`, so a field the DTO does not declare
 * does not get ignored — it rejects the entire request. `extended` was not
 * declared, so the client could not send the page's advanced half without
 * breaking the base fields that did work, and chose (correctly) to send only
 * what the endpoint accepted. These tests pin the contract that ends that.
 */
const pipe = new ValidationPipe({
  whitelist: true,
  forbidNonWhitelisted: true,
  transform: true,
});

function validate(body: Record<string, unknown>) {
  return pipe.transform(body, {
    type: 'body',
    metatype: UpdatePartnerPreferenceDto,
  });
}

describe('UpdatePartnerPreferenceDto', () => {
  it('accepts the advanced preferences blob and keeps every key', async () => {
    const extended = {
      diet: 'Vegetarian',
      familyType: 'Nuclear',
      importance: { diet: 'high' },
      acceptsDivorcee: false,
      preferredCountries: ['India', 'UAE'],
    };

    const result = (await validate({
      minAge: 25,
      extended,
    })) as UpdatePartnerPreferenceDto;

    // Nothing inside the blob is validated or stripped — its shape belongs to
    // the Flutter model and may change without a backend redeploy.
    expect(result.extended).toEqual(extended);
    expect(result.minAge).toBe(25);
  });

  it('accepts a body with no `extended` at all — older app builds keep working', async () => {
    const result = (await validate({
      preferredReligions: ['Hindu'],
    })) as UpdatePartnerPreferenceDto;

    expect(result.extended).toBeUndefined();
    expect(result.preferredReligions).toEqual(['Hindu']);
  });

  it('rejects an `extended` that is not an object', async () => {
    await expect(validate({ extended: 'nope' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('still rejects a genuinely unknown field', async () => {
    // The whitelist is doing its job; `extended` is now a declared escape
    // hatch, not a hole in it.
    await expect(
      validate({ extended: {}, somethingInvented: true }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('accepts an explicit null for a range bound ("Any"), unchanged', async () => {
    const result = (await validate({
      minAge: null,
      maxAge: null,
    })) as UpdatePartnerPreferenceDto;

    expect(result.minAge).toBeNull();
    expect(result.maxAge).toBeNull();
  });
});
