import {
  afterEach,
  beforeAll,
  describe,
  expect,
  mock,
  spyOn,
  test
} from 'bun:test';
import { encoder, toBase64Url } from '../encoding';
import relay from '../index';
import { TICKET_LIFETIME_MS } from '../tickets';
import type { TEnv, TRateLimiter } from '../types';

/**
 * apple is not reached: fetch is spied for its two origins, so everything up to the request
 * the relay would send is covered, and apple's answers are fed back in.
 */

const RELAY = 'https://relay.test';
const DEVICE_TOKEN = 'ab'.repeat(32);

type TServer = { key: string; privateKey: CryptoKey };

const allow: TRateLimiter = { limit: async () => ({ success: true }) };
const deny: TRateLimiter = { limit: async () => ({ success: false }) };

let env: TEnv;
let server: TServer;
let otherServer: TServer;

const toPem = (der: ArrayBuffer) =>
  `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...new Uint8Array(der)))}\n-----END PRIVATE KEY-----`;

const createServer = async (): Promise<TServer> => {
  // bun types an ed25519 generateKey as a single key, it returns a pair
  const pair = (await crypto.subtle.generateKey({ name: 'Ed25519' }, true, [
    'sign',
    'verify'
  ])) as unknown as CryptoKeyPair;
  const { x } = await crypto.subtle.exportKey('jwk', pair.publicKey);

  return { key: x!, privateKey: pair.privateKey };
};

const createApnsKey = async () => {
  const pair = (await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify']
  )) as CryptoKeyPair;

  return toPem(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
};

beforeAll(async () => {
  [server, otherServer] = await Promise.all([createServer(), createServer()]);

  env = {
    TICKET_SECRET: toBase64Url(crypto.getRandomValues(new Uint8Array(32))),
    APNS_TOPIC: 'com.sharkord.ios',
    APNS_TEAM_ID: 'TEAM123456',
    APNS_KEY_ID: 'PRODKEY123',
    APNS_KEY: await createApnsKey(),
    APNS_SANDBOX_KEY_ID: 'SANDKEY123',
    APNS_SANDBOX_KEY: await createApnsKey(),
    TICKETS_LIMITER: allow,
    SERVER_LIMITER: allow,
    DEVICE_LIMITER: allow
  };
});

afterEach(() => {
  mock.restore();
  env.TICKETS_LIMITER = allow;
  env.SERVER_LIMITER = allow;
  env.DEVICE_LIMITER = allow;
});

const post = (
  path: string,
  body: string,
  headers: Record<string, string> = {}
) =>
  relay.fetch(
    new Request(`${RELAY}${path}`, { method: 'POST', body, headers }),
    env
  );

const requestTicket = async (
  input: Record<string, unknown> = {
    deviceToken: DEVICE_TOKEN,
    sandbox: false,
    serverKey: server.key
  }
) => post('/v1/tickets', JSON.stringify(input));

const getTicket = async (serverKey = server.key, sandbox = false) => {
  const response = await requestTicket({
    deviceToken: DEVICE_TOKEN,
    sandbox,
    serverKey
  });

  return (await response.json()) as {
    id: string;
    ticket: string;
    expiresAt: number;
  };
};

const signedPush = async (
  body: Record<string, unknown>,
  signer: TServer = server,
  timestamp = Date.now()
) => {
  const text = JSON.stringify(body);
  const signature = await crypto.subtle.sign(
    { name: 'Ed25519' },
    signer.privateKey,
    encoder.encode(`${timestamp}\n${text}`)
  );

  return post('/v1/push', text, {
    'x-sharkord-timestamp': `${timestamp}`,
    'x-sharkord-signature': toBase64Url(new Uint8Array(signature))
  });
};

const spyOnApple = (status = 200, reason?: string) =>
  spyOn(globalThis, 'fetch').mockResolvedValue(
    new Response(reason ? JSON.stringify({ reason }) : '', { status })
  );

describe('POST /v1/tickets', () => {
  test('should issue a ticket and a stable id for one device on one server', async () => {
    const first = await getTicket();
    const second = await getTicket();

    expect(first.id).toMatch(/^[0-9a-f]{64}$/);
    expect(second.id).toBe(first.id);
    expect(second.ticket).not.toBe(first.ticket);
    expect(first.expiresAt).toBeGreaterThan(Date.now());
  });

  test('should give the same device a different id on another server', async () => {
    const [mine, theirs] = await Promise.all([
      getTicket(server.key),
      getTicket(otherServer.key)
    ]);

    expect(theirs.id).not.toBe(mine.id);
  });

  test('should refuse a device token that is not hex', async () => {
    const response = await requestTicket({
      deviceToken: 'not-a-token',
      sandbox: false,
      serverKey: server.key
    });

    expect(response.status).toBe(400);
  });

  test('should refuse a server key that is not an ed25519 key', async () => {
    const response = await requestTicket({
      deviceToken: DEVICE_TOKEN,
      sandbox: false,
      serverKey: 'short'
    });

    expect(response.status).toBe(400);
  });

  test('should refuse a body that is not json', async () => {
    const response = await post('/v1/tickets', 'nope');

    expect(response.status).toBe(400);
  });

  test('should refuse once the caller is rate limited', async () => {
    env.TICKETS_LIMITER = deny;

    const response = await requestTicket();

    expect(response.status).toBe(429);
  });
});

describe('POST /v1/push', () => {
  test("should send the encrypted payload to the ticket's device", async () => {
    const { ticket } = await getTicket();
    const spy = spyOnApple();

    const response = await signedPush({ ticket, encrypted: 'ciphertext' });

    expect(response.status).toBe(200);
    expect(spy).toHaveBeenCalledTimes(1);

    const [url, init] = spy.mock.calls[0]!;
    const headers = init!.headers as Record<string, string>;
    const body = JSON.parse(init!.body as string);

    expect(url).toBe(`https://api.push.apple.com/3/device/${DEVICE_TOKEN}`);
    expect(headers['apns-topic']).toBe('com.sharkord.ios');
    expect(headers.authorization).toStartWith('bearer ');
    expect(body.encrypted).toBe('ciphertext');
    expect(body.aps['mutable-content']).toBe(1);
  });

  test('should use the sandbox for a development build', async () => {
    const { ticket } = await getTicket(server.key, true);
    const spy = spyOnApple();

    await signedPush({ ticket, encrypted: 'ciphertext' });

    expect(spy.mock.calls[0]![0]).toStartWith(
      'https://api.sandbox.push.apple.com/'
    );
  });

  test('should refuse a ticket issued to another server', async () => {
    const { ticket } = await getTicket(otherServer.key);
    const spy = spyOnApple();

    const response = await signedPush({ ticket, encrypted: 'ciphertext' });

    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ reason: 'TicketNotForServer' });
    expect(spy).not.toHaveBeenCalled();
  });

  test('should refuse a body changed after it was signed', async () => {
    const { ticket } = await getTicket();
    const timestamp = Date.now();
    const signature = await crypto.subtle.sign(
      { name: 'Ed25519' },
      server.privateKey,
      encoder.encode(
        `${timestamp}\n${JSON.stringify({ ticket, encrypted: 'a' })}`
      )
    );
    const spy = spyOnApple();

    const response = await post(
      '/v1/push',
      JSON.stringify({ ticket, encrypted: 'b' }),
      {
        'x-sharkord-timestamp': `${timestamp}`,
        'x-sharkord-signature': toBase64Url(new Uint8Array(signature))
      }
    );

    expect(response.status).toBe(403);
    expect(spy).not.toHaveBeenCalled();
  });

  test('should refuse a request signed too long ago', async () => {
    const { ticket } = await getTicket();

    const response = await signedPush(
      { ticket, encrypted: 'ciphertext' },
      server,
      Date.now() - 10 * 60 * 1000
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ reason: 'StaleRequest' });
  });

  test('should answer with a dead ticket for one it did not issue', async () => {
    const response = await signedPush({
      ticket: toBase64Url(crypto.getRandomValues(new Uint8Array(80))),
      encrypted: 'ciphertext'
    });

    expect(response.status).toBe(410);
    expect(await response.json()).toEqual({ reason: 'BadTicket' });
  });

  test('should answer with a dead ticket once it has expired', async () => {
    const { ticket } = await getTicket();
    const now = Date.now();

    spyOn(Date, 'now').mockReturnValue(now + TICKET_LIFETIME_MS + 1);

    const response = await signedPush(
      { ticket, encrypted: 'ciphertext' },
      server,
      now + TICKET_LIFETIME_MS + 1
    );

    expect(response.status).toBe(410);
    expect(await response.json()).toEqual({ reason: 'ExpiredTicket' });
  });

  test('should refuse a payload too large for apple', async () => {
    const { ticket } = await getTicket();

    const response = await signedPush({
      ticket,
      encrypted: 'a'.repeat(3501)
    });

    expect(response.status).toBe(413);
  });

  test('should refuse a request without a signature', async () => {
    const response = await post(
      '/v1/push',
      JSON.stringify({ ticket: 'x', encrypted: 'y' })
    );

    expect(response.status).toBe(400);
  });

  test('should refuse once the server is rate limited', async () => {
    const { ticket } = await getTicket();
    const spy = spyOnApple();

    env.SERVER_LIMITER = deny;

    const response = await signedPush({ ticket, encrypted: 'ciphertext' });

    expect(response.status).toBe(429);
    expect(spy).not.toHaveBeenCalled();
  });

  test('should refuse once the device is rate limited', async () => {
    const { ticket } = await getTicket();

    env.DEVICE_LIMITER = deny;

    const response = await signedPush({ ticket, encrypted: 'ciphertext' });

    expect(response.status).toBe(429);
  });

  test("should pass apple's answer for a dead token back to the server", async () => {
    const { ticket } = await getTicket();

    spyOnApple(410, 'Unregistered');

    const response = await signedPush({ ticket, encrypted: 'ciphertext' });

    expect(response.status).toBe(410);
    expect(await response.json()).toEqual({ reason: 'Unregistered' });
  });
});

describe('other requests', () => {
  test('should answer an unknown path with not found', async () => {
    const response = await post('/v1/nothing', '{}');

    expect(response.status).toBe(404);
  });

  test('should refuse anything but POST', async () => {
    const response = await relay.fetch(new Request(`${RELAY}/v1/push`), env);

    expect(response.status).toBe(405);
  });
});
