import { sendToApns } from './apns';
import { verifyServerSignature } from './server-signature';
import { issueTicket, openTicket } from './tickets';
import type { TEnv } from './types';

// apple caps a payload at 4096 bytes, and the relay's own wrapper takes some of that
const MAX_ENCRYPTED_LENGTH = 3500;
const MAX_BODY_LENGTH = 8192;

// how far a server's clock may be from ours. it also bounds how long a captured request
// can be replayed, which at worst repeats a notification the device already got
const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000;

const DEVICE_TOKEN_PATTERN = /^[0-9a-f]{64,200}$/;
// an ed25519 public key, 32 bytes as unpadded base64url
const SERVER_KEY_PATTERN = /^[A-Za-z0-9_-]{43}$/;

const json = (status: number, body: Record<string, unknown>) =>
  Response.json(body, { status });

const readBody = async (request: Request) => {
  const text = await request.text();

  if (text.length > MAX_BODY_LENGTH) return undefined;

  return text;
};

const parseJson = (text: string): Record<string, unknown> | undefined => {
  try {
    const value: unknown = JSON.parse(text);

    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, unknown>;
    }
  } catch {
    return undefined;
  }

  return undefined;
};

// called by the app, which hands the result to the one server named in it
const handleTickets = async (request: Request, env: TEnv) => {
  const ip = request.headers.get('cf-connecting-ip') ?? 'unknown';
  const { success } = await env.TICKETS_LIMITER.limit({ key: ip });

  if (!success) return json(429, { reason: 'TooManyRequests' });

  const text = await readBody(request);
  const input = text === undefined ? undefined : parseJson(text);

  if (!input) return json(400, { reason: 'BadRequest' });

  const { deviceToken, sandbox, serverKey } = input;

  if (
    typeof deviceToken !== 'string' ||
    !DEVICE_TOKEN_PATTERN.test(deviceToken) ||
    typeof sandbox !== 'boolean' ||
    typeof serverKey !== 'string' ||
    !SERVER_KEY_PATTERN.test(serverKey)
  ) {
    return json(400, { reason: 'BadRequest' });
  }

  return json(
    200,
    await issueTicket(env.TICKET_SECRET, { deviceToken, sandbox, serverKey })
  );
};

// called by a sharkord server. the answer mirrors apple's: its status, and a reason when it
// is not 200, so the server handles both the same way
const handlePush = async (request: Request, env: TEnv) => {
  const timestamp = request.headers.get('x-sharkord-timestamp');
  const signature = request.headers.get('x-sharkord-signature');
  const text = await readBody(request);

  if (!timestamp || !signature || text === undefined) {
    return json(400, { reason: 'BadRequest' });
  }

  const input = parseJson(text);

  if (
    !input ||
    typeof input.ticket !== 'string' ||
    typeof input.encrypted !== 'string'
  ) {
    return json(400, { reason: 'BadRequest' });
  }

  if (input.encrypted.length > MAX_ENCRYPTED_LENGTH) {
    return json(413, { reason: 'PayloadTooLarge' });
  }

  if (Math.abs(Date.now() - Number(timestamp)) > MAX_CLOCK_SKEW_MS) {
    return json(401, { reason: 'StaleRequest' });
  }

  const ticket = await openTicket(env.TICKET_SECRET, input.ticket);

  if (!ticket) return json(410, { reason: 'BadTicket' });

  // checked before expiry, so a server learns nothing about tickets that are not its own
  const signed = await verifyServerSignature({
    serverKey: ticket.serverKey,
    timestamp,
    body: text,
    signature
  });

  if (!signed) return json(403, { reason: 'TicketNotForServer' });

  if (Date.now() > ticket.expiresAt) {
    return json(410, { reason: 'ExpiredTicket' });
  }

  const [server, device] = await Promise.all([
    env.SERVER_LIMITER.limit({ key: ticket.serverKey }),
    env.DEVICE_LIMITER.limit({ key: ticket.deviceToken })
  ]);

  if (!server.success || !device.success) {
    return json(429, { reason: 'TooManyRequests' });
  }

  const { status, reason } = await sendToApns(env, ticket, input.encrypted);

  return json(status, reason ? { reason } : {});
};

const handleRequest = (request: Request, env: TEnv) => {
  const { pathname } = new URL(request.url);

  if (request.method !== 'POST') return json(405, { reason: 'BadMethod' });

  if (pathname === '/v1/tickets') return handleTickets(request, env);
  if (pathname === '/v1/push') return handlePush(request, env);

  return json(404, { reason: 'NotFound' });
};

export default { fetch: handleRequest };
