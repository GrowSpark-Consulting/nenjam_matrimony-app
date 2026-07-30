import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import type { App } from 'supertest/types';
import { AppConfigModule } from '@app/config';
import { PrismaModule, PrismaService } from '@app/database';
import { RedisModule, RedisService } from '@app/cache';
import { FirebaseModule, FirebaseService } from '@app/firebase';
import { SupportModule } from '../src/modules/support/support.module';
import type { SupportTicketResponseDto } from '../src/modules/support/dto/support-ticket.response.dto';

/**
 * Full support-ticket flow over the real HTTP → FirebaseAuthGuard →
 * TicketsService → Prisma → Postgres path. Only FirebaseService.verifyIdToken
 * is mocked (no real Firebase project in CI/dev); the DB is real. Proves the
 * things unit tests can't: the ValidationPipe + guard are actually applied,
 * data persists across separate requests, ordering is DB-driven, enums
 * serialize to their wire form, and the Prisma `body` column never leaks.
 */
describe('Support tickets (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;

  const UID = 'e2e-support-uid';

  const verifyIdToken = jest.fn((token: string) => {
    if (token === 'token-support') {
      return Promise.resolve({ uid: UID, email: 'support@e2e-test.local' });
    }
    return Promise.reject(new Error('invalid token'));
  });

  const auth = ['Authorization', 'Bearer token-support'] as const;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [
        AppConfigModule,
        PrismaModule,
        RedisModule,
        FirebaseModule,
        SupportModule,
      ],
    })
      .overrideProvider(FirebaseService)
      .useValue({ verifyIdToken })
      // Inert Redis so the guard's UID cache is a no-op (falls through to the
      // DB) and nothing tries to open a real connection during the test.
      .overrideProvider(RedisService)
      .useValue({ getClient: () => ({ status: 'end' }) })
      .compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        transform: true,
        forbidNonWhitelisted: true,
      }),
    );
    await app.init();
    prisma = moduleFixture.get(PrismaService);

    await cleanup();
  });

  afterAll(async () => {
    await cleanup();
    await app.close();
  });

  async function cleanup(): Promise<void> {
    const user = await prisma.user.findUnique({
      where: { firebaseUid: UID },
      select: { id: true },
    });
    if (!user) return;
    await prisma.supportTicket.deleteMany({ where: { userId: user.id } });
    await prisma.user.delete({ where: { id: user.id } });
  }

  it('rejects an unauthenticated request', async () => {
    await request(app.getHttpServer()).get('/support/tickets').expect(401);
  });

  it('rejects an unknown ticket type (DTO @IsEnum via the ValidationPipe)', async () => {
    await request(app.getHttpServer())
      .post('/support/tickets')
      .set(...auth)
      .send({ type: 'notARealType', subject: 'x', message: 'y' })
      .expect(400);
  });

  it('rejects a blank subject', async () => {
    await request(app.getHttpServer())
      .post('/support/tickets')
      .set(...auth)
      .send({ type: 'bugReport', subject: '   ', message: 'y' })
      .expect(400);
  });

  it('creates a ticket and returns the wire shape (no Prisma `body` leak)', async () => {
    const res = await request(app.getHttpServer())
      .post('/support/tickets')
      .set(...auth)
      .send({
        type: 'contactSupport',
        subject: 'Need help',
        message: 'How do I change my email?',
      })
      .expect(201);

    const ticket = res.body as SupportTicketResponseDto;
    expect(ticket).toMatchObject({
      type: 'contactSupport',
      subject: 'Need help',
      message: 'How do I change my email?',
      status: 'open',
    });
    expect(typeof ticket.id).toBe('string');
    expect(typeof ticket.createdAt).toBe('string');
    expect(ticket).not.toHaveProperty('body');
    expect(ticket).not.toHaveProperty('userId');
  });

  it('returns history newest-first in an { items } envelope, with wire enums, persisted across requests', async () => {
    // A second, newer ticket (created after the first above).
    await request(app.getHttpServer())
      .post('/support/tickets')
      .set(...auth)
      .send({
        type: 'bugReport',
        subject: 'Crash on upload',
        message: 'App crashes after photo upload.',
      })
      .expect(201);

    const res = await request(app.getHttpServer())
      .get('/support/tickets')
      .set(...auth)
      .expect(200);

    const body = res.body as { items: SupportTicketResponseDto[] };
    expect(Array.isArray(body.items)).toBe(true);
    expect(body.items).toHaveLength(2);
    // Newest first — the bugReport was created after the contactSupport.
    expect(body.items.map((t) => t.type)).toEqual([
      'bugReport',
      'contactSupport',
    ]);
    // Wire serialization, no leaked columns.
    expect(body.items[0].status).toBe('open');
    expect(body.items[0]).not.toHaveProperty('body');

    // Persistence: a fresh request (new "session") returns the same rows —
    // proving they were written to Postgres, not held in memory.
    const again = await request(app.getHttpServer())
      .get('/support/tickets')
      .set(...auth)
      .expect(200);
    const againBody = again.body as { items: SupportTicketResponseDto[] };
    expect(againBody.items.map((t) => t.id)).toEqual(
      body.items.map((t) => t.id),
    );
  });
});
