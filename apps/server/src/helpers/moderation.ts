import { ActivityLogType, DisconnectCode } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { db } from '../db';
import { invalidateUserSessions } from '../db/mutations/users';
import { publishUser } from '../db/publishers';
import { getLoginIpsForUser } from '../db/queries/ip-bans';
import { ipBans, users } from '../db/schema';
import { eventBus } from '../plugins/event-bus';
import { enqueueActivityLog } from '../queues/activity-log';
import { invariant } from '../utils/invariant';
import type { Context } from '../utils/trpc';
import { disconnectUser, getUserIp, getUserWsCount } from '../utils/wss';
import { isPrivateIP } from './network';

type TUserSessions = {
  count: () => number;
  close: (code: DisconnectCode, reason?: string) => void;
};

const serverUserSessions = (userId: number): TUserSessions => ({
  count: () => getUserWsCount(userId),
  close: (code, reason) => disconnectUser(userId, code, reason)
});

const ctxUserSessions = (ctx: Context, userId: number): TUserSessions => ({
  count: () => ctx.getUserWs(userId).length,
  close: (code, reason) =>
    ctx.getUserWs(userId).forEach((socket) => socket.close(code, reason))
});

const assertUserExists = async (userId: number) => {
  const targetUser = await db
    .select({ id: users.id })
    .from(users)
    .where(eq(users.id, userId))
    .limit(1)
    .get();

  invariant(targetUser, {
    code: 'NOT_FOUND',
    message: 'User not found.'
  });
};

// the addresses an ip ban takes: every one the account signed in from and the one it is on now.
// a private or loopback address is never banned, behind a proxy that does not pass the real
// address on it is everyone's, and neither is the moderator's own
const getIpsToBan = async (userId: number, actorUserId: number | null) => {
  const loginIps = await getLoginIpsForUser(userId);
  const currentIp = getUserIp(userId);
  const actorIp = actorUserId === null ? undefined : getUserIp(actorUserId);
  const ips = new Set(currentIp ? [...loginIps, currentIp] : loginIps);

  return [...ips].filter((ip) => !isPrivateIP(ip) && ip !== actorIp);
};

const banUser = async (
  userId: number,
  reason: string | undefined,
  actorUserId: number | null,
  sessions: TUserSessions,
  { banIps = false }: { banIps?: boolean } = {}
) => {
  await assertUserExists(userId);

  // read before the sessions close, which forgets the address they are on
  const ipsToBan = banIps ? await getIpsToBan(userId, actorUserId) : [];

  // closed before the row changes, so a banned session cannot act in the gap
  sessions.close(DisconnectCode.BANNED, reason);

  const now = Date.now();

  db.transaction((tx) => {
    tx.update(users)
      .set({
        banned: true,
        banReason: reason ?? null,
        bannedAt: now
      })
      .where(eq(users.id, userId))
      .run();

    if (ipsToBan.length > 0) {
      tx.insert(ipBans)
        .values(ipsToBan.map((ip) => ({ ip, userId, createdAt: now })))
        .onConflictDoNothing()
        .run();
    }
  });

  publishUser(userId, 'update');

  eventBus.emit('user:banned', {
    userId,
    reason,
    actorUserId: actorUserId ?? undefined
  });

  enqueueActivityLog({
    type: ActivityLogType.USER_BANNED,
    userId,
    details: { reason, bannedBy: actorUserId ?? undefined }
  });
};

const unbanUser = async (userId: number, actorUserId: number | null) => {
  await assertUserExists(userId);

  db.transaction((tx) => {
    tx.update(users)
      .set({ banned: false, banReason: null, bannedAt: null })
      .where(eq(users.id, userId))
      .run();

    tx.delete(ipBans).where(eq(ipBans.userId, userId)).run();
  });

  publishUser(userId, 'update');

  eventBus.emit('user:unbanned', {
    userId,
    actorUserId: actorUserId ?? undefined
  });

  enqueueActivityLog({
    type: ActivityLogType.USER_UNBANNED,
    userId,
    details: { unbannedBy: actorUserId ?? undefined }
  });
};

const kickUser = async (
  userId: number,
  reason: string | undefined,
  actorUserId: number | null,
  sessions: TUserSessions
) => {
  invariant(sessions.count() > 0, {
    code: 'NOT_FOUND',
    message: 'User is not connected'
  });

  await invalidateUserSessions(userId);

  sessions.close(DisconnectCode.KICKED, reason);

  eventBus.emit('user:kicked', {
    userId,
    reason,
    actorUserId: actorUserId ?? undefined
  });

  enqueueActivityLog({
    type: ActivityLogType.USER_KICKED,
    userId,
    details: { reason, kickedBy: actorUserId ?? undefined }
  });
};

export { banUser, ctxUserSessions, kickUser, serverUserSessions, unbanUser };
export type { TUserSessions };
