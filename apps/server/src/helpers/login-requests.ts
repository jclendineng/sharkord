import { LOGIN_LINK_TTL_MS } from '@sharkord/shared';
import { randomUUIDv7 } from 'bun';
import { randomBytes } from 'crypto';
import { and, eq, lt } from 'drizzle-orm';
import { db } from '../db';
import { loginRequests } from '../db/schema';
import { hashLoginSecret, matchesLoginLinkSecret } from './login-links';

// a device without a camera asking to be signed in. the token goes in its qr code for the
// signed in device to scan, the poll key stays with the asking device and collects the session.
// requests that ran out are swept away with every new one, nobody else ever reads them
const createLoginRequest = async (info: {
  os?: string;
  device?: string;
  ip?: string;
}) => {
  const id = randomUUIDv7();
  const secret = randomBytes(24).toString('base64url');
  const pollKey = randomBytes(24).toString('base64url');
  const now = Date.now();
  const expiresAt = now + LOGIN_LINK_TTL_MS;

  db.transaction((tx) => {
    tx.delete(loginRequests).where(lt(loginRequests.expiresAt, now)).run();
    tx.insert(loginRequests)
      .values({
        id,
        secretHash: hashLoginSecret(secret),
        pollKeyHash: hashLoginSecret(pollKey),
        status: 'waiting',
        requestOs: info.os ?? null,
        requestDevice: info.device ?? null,
        requestIp: info.ip ?? null,
        createdAt: now,
        expiresAt
      })
      .run();
  });

  return { id, token: `${id}.${secret}`, pollKey, expiresAt };
};

// the request a scanned token names, when its secret is right
const getLoginRequestByToken = async (token: string) => {
  const [id, secret] = token.split('.');

  if (!id || !secret) {
    return undefined;
  }

  const row = await db
    .select()
    .from(loginRequests)
    .where(eq(loginRequests.id, id))
    .limit(1)
    .get();

  if (!row || !matchesLoginSecret(secret, row.secretHash)) {
    return undefined;
  }

  return row;
};

// the request the asking device polls, when it brings its own key
const getLoginRequestByPollKey = async (id: string, pollKey: string) => {
  const row = await db
    .select()
    .from(loginRequests)
    .where(eq(loginRequests.id, id))
    .limit(1)
    .get();

  if (!row || !matchesLoginSecret(pollKey, row.pollKeyHash)) {
    return undefined;
  }

  return row;
};

// answered once, by the first signed in device to do so, for its own account
const answerLoginRequest = async (
  id: string,
  userId: number,
  approve: boolean
) => {
  const answered = await db
    .update(loginRequests)
    .set({ userId, status: approve ? 'approved' : 'denied' })
    .where(and(eq(loginRequests.id, id), eq(loginRequests.status, 'waiting')))
    .returning({ id: loginRequests.id });

  return answered.length > 0;
};

const deleteLoginRequest = async (id: string) =>
  db.delete(loginRequests).where(eq(loginRequests.id, id));

const matchesLoginSecret = matchesLoginLinkSecret;

export {
  answerLoginRequest,
  createLoginRequest,
  deleteLoginRequest,
  getLoginRequestByPollKey,
  getLoginRequestByToken
};
