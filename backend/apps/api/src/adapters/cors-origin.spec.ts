import { createServer, type Server as HttpServer } from 'http';
import type { Server } from 'socket.io';
import { RedisIoAdapter } from './redis-io.adapter';
import {
  corsOriginOption,
  isOriginAllowed,
  type OriginPolicy,
} from './cors-origin';

const WEB = 'https://app.nenjam.example';
const OTHER = 'https://evil.example';

const closed: OriginPolicy = { allowedOrigins: [], isDevelopment: false };
const dev: OriginPolicy = { allowedOrigins: [], isDevelopment: true };
const listed: OriginPolicy = { allowedOrigins: [WEB], isDevelopment: false };
const listedInDev: OriginPolicy = {
  allowedOrigins: [WEB],
  isDevelopment: true,
};

describe('origin policy', () => {
  it('an explicit allowlist admits only its own origins, in every environment', () => {
    for (const policy of [listed, listedInDev]) {
      expect(isOriginAllowed(WEB, policy)).toBe(true);
      expect(isOriginAllowed(OTHER, policy)).toBe(false);
      expect(corsOriginOption(policy)).toEqual([WEB]);
    }
  });

  it('with no allowlist, production fails closed and development is open', () => {
    expect(isOriginAllowed(OTHER, closed)).toBe(false);
    expect(corsOriginOption(closed)).toBe(false);
    expect(isOriginAllowed(OTHER, dev)).toBe(true);
    expect(corsOriginOption(dev)).toBe(true);
  });

  it('a request without an Origin (native app, server tool) is not judged here', () => {
    expect(isOriginAllowed(undefined, closed)).toBe(true);
    expect(isOriginAllowed(undefined, listed)).toBe(true);
  });

  it('is exact: no prefix, subdomain or scheme confusion', () => {
    expect(isOriginAllowed(`${WEB}.evil.example`, listed)).toBe(false);
    expect(isOriginAllowed('http://app.nenjam.example', listed)).toBe(false);
    expect(isOriginAllowed(`${WEB}/`, listed)).toBe(false);
  });
});

describe('Socket.IO handshake', () => {
  let http: HttpServer;
  let server: Server;
  let base: string;

  async function start(policy: OriginPolicy): Promise<void> {
    http = createServer();
    await new Promise<void>((resolve) => http.listen(0, '127.0.0.1', resolve));
    const adapter = new RedisIoAdapter(http as never, {} as never, policy);
    server = adapter.createIOServer(0);
    const address = http.address();
    const port = typeof address === 'object' && address ? address.port : 0;
    base = `http://127.0.0.1:${port}/socket.io/?EIO=4&transport=polling`;
  }

  const handshake = (origin?: string) =>
    fetch(base, { headers: origin ? { Origin: origin } : {} });

  afterEach(async () => {
    await new Promise<void>((resolve) => void server.close(() => resolve()));
    http.close();
  });

  it('refuses a browser origin that is not on the allowlist', async () => {
    await start(listed);
    expect((await handshake(OTHER)).status).toBe(403);
  });

  it('admits an allowlisted origin, without credentialed CORS', async () => {
    await start(listed);
    const res = await handshake(WEB);
    expect(res.status).toBe(200);
    expect(res.headers.get('access-control-allow-origin')).toBe(WEB);
    expect(res.headers.get('access-control-allow-credentials')).toBeNull();
  });

  it('refuses every browser origin in production when no allowlist is set', async () => {
    await start(closed);
    expect((await handshake(WEB)).status).toBe(403);
  });

  it('still admits a native client that sends no Origin', async () => {
    await start(closed);
    expect((await handshake()).status).toBe(200);
  });
});
