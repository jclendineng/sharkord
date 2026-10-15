import { and, eq, isNull, ne, or } from 'drizzle-orm';
import { db } from '../../db';
import { getSettings } from '../../db/queries/server';
import { pushDevices, users } from '../../db/schema';
import type { TConnectionInfo } from '../../types';

// every other device the account is signed in on, the one that just signed in left out. do not
// disturb does not hold this back, it is about the account's safety rather than a message
const getLoginNotificationDevices = (userId: number, sessionId: string) =>
  db
    .select({
      id: pushDevices.id,
      token: pushDevices.token,
      sandbox: pushDevices.sandbox
    })
    .from(pushDevices)
    .innerJoin(users, eq(users.id, pushDevices.userId))
    .where(
      and(
        eq(pushDevices.userId, userId),
        eq(users.tokenVersion, pushDevices.tokenVersion),
        or(isNull(pushDevices.sessionId), ne(pushDevices.sessionId, sessionId))
      )
    )
    .all();

// discord's new login alert: what signed in, and where. a tap opens the server's devices
const buildLoginPayload = async (info: TConnectionInfo | undefined) => {
  const settings = await getSettings();
  const device = [info?.os, info?.device].filter(Boolean).join(' · ');

  return {
    aps: {
      alert: {
        title: 'New login detected',
        body: device
          ? `${device} signed in to your account on ${settings.name}.`
          : `A new login was detected on your account on ${settings.name}.`
      },
      sound: 'default'
    },
    serverId: settings.serverId,
    kind: 'newLogin'
  };
};

export { buildLoginPayload, getLoginNotificationDevices };
