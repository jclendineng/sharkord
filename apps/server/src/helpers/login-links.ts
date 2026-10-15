import { LOGIN_LINK_TTL_MS } from '@sharkord/shared';
import { randomUUIDv7 } from 'bun';
import { createHash, randomBytes, timingSafeEqual } from 'crypto';
import { and, eq } from 'drizzle-orm';
import { db } from '../db';
import { loginLinks } from '../db/schema';

type TLoginLinkStatus = 'waiting' | 'claimed' | 'approved' | 'denied';

const hash = (value: string) =>
  createHash('sha256').update(value).digest('hex');

const matches = (value: string, expectedHash: string | null) => {
  if (!expectedHash) {
    return false;
  }

  const actual = Buffer.from(hash(value));
  const expected = Buffer.from(expectedHash);

  return actual.length === expected.length && timingSafeEqual(actual, expected);
};

// a new qr code for the caller's other device, any older ones of theirs gone with it. the
// token is the link's id and its secret, only the secret's hash is kept
const createLoginLink = async (userId: number) => {
  const id = randomUUIDv7();
  const secret = randomBytes(24).toString('base64url');
  const now = Date.now();
  const expiresAt = now + LOGIN_LINK_TTL_MS;

  db.transaction((tx) => {
    tx.delete(loginLinks).where(eq(loginLinks.userId, userId)).run();
    tx.insert(loginLinks)
      .values({
        id,
        userId,
        secretHash: hash(secret),
        status: 'waiting',
        createdAt: now,
        expiresAt
      })
      .run();
  });

  return { id, token: `${id}.${secret}`, expiresAt };
};

// the link a token names, when its secret is right and it has not run out
const getLoginLinkByToken = async (token: string) => {
  const [id, secret] = token.split('.');

  if (!id || !secret) {
    return undefined;
  }

  const row = await db
    .select()
    .from(loginLinks)
    .where(eq(loginLinks.id, id))
    .limit(1)
    .get();

  if (!row || !matches(secret, row.secretHash) || row.expiresAt < Date.now()) {
    return undefined;
  }

  return row;
};

// the first device to present the token holds it, with a key only it was given
const claimLoginLink = async (
  id: string,
  info: { os?: string; device?: string; ip?: string }
) => {
  const claimKey = randomBytes(24).toString('base64url');

  const claimed = await db
    .update(loginLinks)
    .set({
      status: 'claimed',
      claimKeyHash: hash(claimKey),
      claimedOs: info.os ?? null,
      claimedDevice: info.device ?? null,
      claimedIp: info.ip ?? null
    })
    .where(and(eq(loginLinks.id, id), eq(loginLinks.status, 'waiting')))
    .returning({ id: loginLinks.id });

  return claimed.length > 0 ? claimKey : undefined;
};

const setLoginLinkStatus = async (id: string, status: TLoginLinkStatus) =>
  db.update(loginLinks).set({ status }).where(eq(loginLinks.id, id));

const deleteLoginLink = async (id: string) =>
  db.delete(loginLinks).where(eq(loginLinks.id, id));

export {
  claimLoginLink,
  createLoginLink,
  deleteLoginLink,
  getLoginLinkByToken,
  matches as matchesLoginLinkSecret,
  setLoginLinkStatus
};
export type { TLoginLinkStatus };
