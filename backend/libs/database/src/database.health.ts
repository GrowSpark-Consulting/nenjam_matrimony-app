import { Injectable } from '@nestjs/common';
import { PrismaService } from './prisma.service';

export interface DatabaseHealth {
  status: 'up' | 'down';
  latencyMs?: number;
  error?: string;
}

@Injectable()
export class DatabaseHealthService {
  constructor(private readonly prisma: PrismaService) {}

  async check(): Promise<DatabaseHealth> {
    const start = Date.now();

    try {
      await this.prisma.$queryRaw`SELECT 1`;
      return { status: 'up', latencyMs: Date.now() - start };
    } catch (error) {
      return {
        status: 'down',
        error:
          error instanceof Error ? error.message : 'Unknown database error',
      };
    }
  }
}
