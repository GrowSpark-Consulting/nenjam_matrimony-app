import { BadRequestException, ParseUUIDPipe } from '@nestjs/common';
import { IsInt, IsString, Min, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiValidationPipe, validationFailed } from './validation-failed';

class Child {
  @IsString()
  name!: string;
}

class Body {
  @IsInt()
  @Min(1)
  version!: number;

  @ValidateNested()
  @Type(() => Child)
  child!: Child;
}

async function refusal(promise: Promise<unknown>) {
  try {
    await promise;
  } catch (error) {
    return error as BadRequestException;
  }
  throw new Error('expected a validation failure');
}

describe('validationFailed', () => {
  it('is a 400 with code VALIDATION_FAILED and the messages kept as they are', () => {
    const error = validationFailed(['version must not be less than 1']);
    expect(error.getStatus()).toBe(400);
    expect(error.getResponse()).toEqual({
      statusCode: 400,
      error: 'Bad Request',
      code: 'VALIDATION_FAILED',
      message: ['version must not be less than 1'],
    });
  });

  it('works as ParseUUIDPipe’s exceptionFactory', async () => {
    const pipe = new ParseUUIDPipe({ exceptionFactory: validationFailed });
    const error = await refusal(
      pipe.transform('not-a-uuid', { type: 'param', data: 'id' }),
    );
    expect(error.getResponse()).toMatchObject({ code: 'VALIDATION_FAILED' });
  });
});

describe('ApiValidationPipe', () => {
  const pipe = new ApiValidationPipe({
    whitelist: true,
    transform: true,
    forbidNonWhitelisted: true,
  });
  const metadata = { type: 'body' as const, metatype: Body };

  it('answers with VALIDATION_FAILED and Nest’s usual messages, nested ones included', async () => {
    const error = await refusal(
      pipe.transform({ version: 0, child: { name: 7 }, extra: true }, metadata),
    );
    const body = error.getResponse() as { code: string; message: string[] };
    expect(body.code).toBe('VALIDATION_FAILED');
    expect(body.message).toEqual(
      expect.arrayContaining([
        'version must not be less than 1',
        'child.name must be a string',
        'property extra should not exist',
      ]),
    );
  });

  it('passes a valid body through', async () => {
    await expect(
      pipe.transform({ version: 2, child: { name: 'x' } }, metadata),
    ).resolves.toMatchObject({ version: 2 });
  });
});
