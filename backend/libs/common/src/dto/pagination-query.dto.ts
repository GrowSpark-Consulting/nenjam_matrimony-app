import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';

/**
 * Shared page/limit query DTO for every list endpoint. Query params arrive as
 * strings, so `@Type(() => Number)` coerces them before validation (the global
 * ValidationPipe runs with `transform: true`). `skip`/`take` are derived here
 * so callers never recompute the offset math.
 *
 * `limit` is capped at 100 to bound worst-case payload/row scans. A `cursor`
 * field is intentionally reserved (see below) so keyset pagination can be added
 * later without a breaking query-shape change — the current offset pagination
 * stays the default.
 */
export class PaginationQueryDto {
  @ApiPropertyOptional({
    description: '1-based page number.',
    default: 1,
    minimum: 1,
    example: 1,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({
    description: 'Items per page.',
    default: 20,
    minimum: 1,
    maximum: 100,
    example: 20,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 20;

  get pageNumber(): number {
    return this.page ?? 1;
  }

  get take(): number {
    return this.limit ?? 20;
  }

  get skip(): number {
    return (this.pageNumber - 1) * this.take;
  }
}
