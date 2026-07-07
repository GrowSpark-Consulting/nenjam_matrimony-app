import { SetMetadata } from '@nestjs/common';

// TODO: finalize metadata key/value once the guard reading it is implemented.
export const Roles = (...roles: string[]) => SetMetadata('roles', roles);
