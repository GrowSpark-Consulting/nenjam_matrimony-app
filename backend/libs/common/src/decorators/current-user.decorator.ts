import { createParamDecorator } from '@nestjs/common';

// TODO: implement extraction logic once the request shape is finalized.
export const CurrentUser = createParamDecorator(() => undefined);
