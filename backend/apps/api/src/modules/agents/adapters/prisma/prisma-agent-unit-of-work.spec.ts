import type { PrismaClient } from '@app/database';
import { asTx, unwrapTx } from './prisma-agent-tx';
import { PrismaAgentUnitOfWork } from './prisma-agent-unit-of-work';

/** A stand-in for `prisma.$transaction` that hands the callback a marker client. */
function fakePrisma() {
  const client = { marker: 'tx-client' };
  const calls: unknown[] = [];
  const transaction = jest.fn(
    async (fn: (c: unknown) => Promise<unknown>, options?: unknown) => {
      calls.push(options);
      return fn(client);
    },
  );
  const prisma = { $transaction: transaction } as unknown as Pick<
    PrismaClient,
    '$transaction'
  >;
  return { prisma, transaction, client, calls };
}

describe('PrismaAgentUnitOfWork', () => {
  it('runs the callback in a Prisma transaction and returns its result', async () => {
    const { prisma, client, transaction } = fakePrisma();
    const uow = new PrismaAgentUnitOfWork(prisma);
    const result = await uow.run((tx) => Promise.resolve(unwrapTx(tx)));
    expect(result).toBe(client);
    expect(transaction).toHaveBeenCalledTimes(1);
  });

  it('rethrows the callback error unchanged (Prisma rolls back)', async () => {
    const { prisma } = fakePrisma();
    const uow = new PrismaAgentUnitOfWork(prisma);
    const boom = new Error('boom');
    await expect(uow.run(() => Promise.reject(boom))).rejects.toBe(boom);
  });

  it('refuses a nested run', async () => {
    const { prisma, transaction } = fakePrisma();
    const uow = new PrismaAgentUnitOfWork(prisma);
    await expect(
      uow.run(() => uow.run(() => Promise.resolve(1))),
    ).rejects.toThrow('Nested AgentUnitOfWork.run is not supported.');
    expect(transaction).toHaveBeenCalledTimes(1);
  });

  it('allows a new run after the previous one finished or failed', async () => {
    const { prisma } = fakePrisma();
    const uow = new PrismaAgentUnitOfWork(prisma);
    await expect(uow.run(() => Promise.reject(new Error('x')))).rejects.toThrow(
      'x',
    );
    await expect(uow.run(() => Promise.resolve('ok'))).resolves.toBe('ok');
  });

  it('passes the transaction options it was given, and only those', async () => {
    const full = fakePrisma();
    await new PrismaAgentUnitOfWork(full.prisma, {
      maxWaitMs: 111,
      timeoutMs: 222,
      isolationLevel: 'Serializable',
    }).run(() => Promise.resolve(1));
    expect(full.calls[0]).toEqual({
      maxWait: 111,
      timeout: 222,
      isolationLevel: 'Serializable',
    });

    const empty = fakePrisma();
    await new PrismaAgentUnitOfWork(empty.prisma).run(() => Promise.resolve(1));
    expect(empty.calls[0]).toEqual({});
  });

  it('refuses a tx whose run has finished', async () => {
    const { prisma } = fakePrisma();
    const uow = new PrismaAgentUnitOfWork(prisma);
    const leaked = await uow.run((tx) => Promise.resolve(tx));
    expect(() => unwrapTx(leaked)).toThrow(
      'The transaction has already finished.',
    );
  });
});

describe('asTx / unwrapTx', () => {
  it('round-trips a client', () => {
    const client = { marker: 'c' } as never;
    expect(unwrapTx(asTx(client))).toBe(client);
  });

  it('refuses an object that was not made by asTx', () => {
    expect(() => unwrapTx({} as never)).toThrow(TypeError);
    expect(() => unwrapTx({ client: {} } as never)).toThrow(TypeError);
  });
});
