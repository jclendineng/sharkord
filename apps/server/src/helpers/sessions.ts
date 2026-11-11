import { DisconnectCode } from '@sharkord/shared';
import { randomUUIDv7 } from 'bun';
import { and, eq, ne } from 'drizzle-orm';
import jwt from 'jsonwebtoken';
import { db } from '../db';
import { getServerToken } from '../db/queries/server';
import { sessions } from '../db/schema';
import { enqueueLoginNotification } from '../queues/push-notifications';
import type { TConnectionInfo } from '../types';
import { disconnectSessions } from '../utils/wss';

// no expiry: a session lasts until it is signed out, ended from the devices list or ended by a
// password change, which deletes its row or bumps the token version. a week's expiry signed
// out every device nobody had opened in that time, and the apps only showed reconnecting
const signSessionToken = async (
  userId: number,
  tokenVersion: number,
  sessionId: string
) => jwt.sign({ userId, tokenVersion, sessionId }, await getServerToken());

// every sign in goes through here, password and oidc alike
const createSessionToken = async (
  userId: number,
  tokenVersion: number,
  info: TConnectionInfo | undefined
) => {
  const sessionId = randomUUIDv7();
  const now = Date.now();

  await db.insert(sessions).values({
    id: sessionId,
    userId,
    os: info?.os,
    device: info?.device,
    userAgent: info?.userAgent,
    ip: info?.ip,
    createdAt: now,
    lastActiveAt: now
  });

  enqueueLoginNotification(userId, sessionId, info);

  return signSessionToken(userId, tokenVersion, sessionId);
};

const revokeSession = async (userId: number, sessionId: string) => {
  const deleted = await db
    .delete(sessions)
    .where(and(eq(sessions.id, sessionId), eq(sessions.userId, userId)))
    .returning({ id: sessions.id });

  disconnectSessions(
    userId,
    deleted.map(({ id }) => id),
    DisconnectCode.KICKED,
    'You were signed out of this device'
  );

  return deleted.length > 0;
};

const revokeOtherSessions = async (
  userId: number,
  keepSessionId: string | undefined
) => {
  const deleted = await db
    .delete(sessions)
    .where(
      keepSessionId
        ? and(eq(sessions.userId, userId), ne(sessions.id, keepSessionId))
        : eq(sessions.userId, userId)
    )
    .returning({ id: sessions.id });

  disconnectSessions(
    userId,
    deleted.map(({ id }) => id),
    DisconnectCode.KICKED,
    'You were signed out of this device'
  );

  return deleted.length;
};

export {
  createSessionToken,
  revokeOtherSessions,
  revokeSession,
  signSessionToken
};
