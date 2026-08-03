/**
 * End-to-end verification of the email pipeline.
 *
 *   pnpm verify:email you@example.com
 *
 * Boots a Nest context that is BOTH producer and consumer (MailModule.forWorker),
 * enqueues an OTP and a Welcome email, then polls the EmailLog table until each
 * row reaches a terminal state. Exercises the real path end to end:
 *
 *   MailService -> BullMQ/Redis -> EmailProcessor -> Handlebars -> provider -> Postgres
 *
 * With RESEND_API_KEY set this delivers real mail. Without it the no-op provider
 * is bound, so everything except the outbound HTTP call still runs — which makes
 * this safe to run in CI as a smoke test.
 *
 * Note on Resend's shared sender: `onboarding@resend.dev` only delivers to the
 * email address that owns the Resend account. Sending anywhere else returns a
 * 403 `invalid_from_address`. Use your own verified domain to reach real users.
 */
import { config } from 'dotenv';
config({ path: '.env' });
config({ path: '.env.local', override: true });

import { Logger, Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppConfigModule, AppConfigService } from '@app/config';
import { PrismaModule, PrismaService } from '@app/database';
import { QueueModule } from '@app/queue';
import { MailModule, MailService } from '@app/mail';

@Module({
  imports: [AppConfigModule, PrismaModule, QueueModule, MailModule.forWorker()],
})
class VerifyEmailModule {}

const TERMINAL = new Set(['SENT', 'FAILED', 'DEAD_LETTER']);

async function main(): Promise<void> {
  const to = process.argv[2] ?? process.env.MAIL_TEST_TO;
  if (!to) {
    console.error('Usage: pnpm verify:email <recipient@example.com>');
    process.exit(1);
  }

  // Quiet the boot banners so the report below is the only output that matters.
  const app = await NestFactory.createApplicationContext(VerifyEmailModule, {
    logger: ['warn', 'error'],
  });
  const logger = new Logger('verify:email');

  const mail = app.get(MailService);
  const prisma = app.get(PrismaService);
  const configService = app.get(AppConfigService);

  const provider = configService.mail.provider;
  console.log(
    `\nProvider  : ${provider}${provider === 'noop' ? '  (RESEND_API_KEY unset — nothing will actually be delivered)' : ''}`,
  );
  console.log(`From      : ${configService.mail.from}`);
  console.log(`Recipient : ${to}\n`);

  const ids: { label: string; id?: string }[] = [
    {
      label: 'OTP',
      id: await mail.sendOtp(to, { code: '482910', expiryMinutes: 10 }),
    },
    {
      label: 'Welcome',
      id: await mail.sendWelcome(to, { firstName: 'Asha' }),
    },
  ];
  logger.log(`Enqueued ${ids.length} email(s); waiting for the worker...`);

  const deadline = Date.now() + 60_000;
  const results = new Map<
    string,
    {
      status: string;
      provider: string;
      messageId: string | null;
      error: string | null;
      attempts: number;
    }
  >();

  while (Date.now() < deadline && results.size < ids.length) {
    for (const { id } of ids) {
      if (!id || results.has(id)) continue;
      const row = await prisma.emailLog.findUnique({ where: { id } });
      if (row && TERMINAL.has(row.status)) {
        results.set(id, {
          status: row.status,
          provider: row.provider,
          messageId: row.providerMessageId,
          error: row.error,
          attempts: row.attempts,
        });
      }
    }
    if (results.size < ids.length)
      await new Promise((r) => setTimeout(r, 1000));
  }

  console.log('\n──────── RESULT ────────');
  let failed = 0;
  for (const { label, id } of ids) {
    const row = id ? results.get(id) : undefined;
    if (!row) {
      console.log(
        `✖ ${label.padEnd(8)} no terminal state within 60s (is the worker running?)`,
      );
      failed++;
      continue;
    }
    const ok = row.status === 'SENT';
    if (!ok) failed++;
    console.log(
      `${ok ? '✔' : '✖'} ${label.padEnd(8)} ${row.status.padEnd(12)} provider=${row.provider} ` +
        `attempts=${row.attempts}` +
        (row.messageId ? ` id=${row.messageId}` : '') +
        (row.error ? `\n            error: ${row.error}` : ''),
    );
  }

  if (provider === 'noop' && failed === 0) {
    console.log(
      '\nPipeline verified end to end. Nothing was delivered — set RESEND_API_KEY and re-run to send for real.',
    );
  }

  await app.close();
  process.exit(failed === 0 ? 0 : 1);
}

void main().catch((error) => {
  console.error(error);
  process.exit(1);
});
