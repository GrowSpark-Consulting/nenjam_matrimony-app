import {
  BadRequestException,
  ValidationPipe,
  type ValidationPipeOptions,
} from '@nestjs/common';

/**
 * The 400 every request-validation failure answers with:
 *
 *   { statusCode: 400, error: 'Bad Request', code: 'VALIDATION_FAILED', message }
 *
 * `message` is what Nest has always sent — a list of readable problems, or
 * one string — so existing clients keep working; branch on `code`.
 *
 * Use it on id parameters as
 * `new ParseUUIDPipe({ exceptionFactory: validationFailed })`; bodies and
 * queries get it from ApiValidationPipe, installed globally in main.ts.
 */
export function validationFailed(
  message: string | string[],
): BadRequestException {
  return new BadRequestException({
    statusCode: 400,
    error: 'Bad Request',
    code: 'VALIDATION_FAILED',
    message,
  });
}

/** Nest's ValidationPipe with the same messages, answered through
 *  `validationFailed`. */
export class ApiValidationPipe extends ValidationPipe {
  constructor(options?: ValidationPipeOptions) {
    super(options);
    this.exceptionFactory = (errors) =>
      validationFailed(this.flattenValidationErrors(errors));
  }
}
