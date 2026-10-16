import { eq } from 'drizzle-orm';
import { db } from '..';
import { ipBans, logins } from '../schema';

const isIpBanned = async (ip: string | undefined): Promise<boolean> => {
  if (!ip) return false;

  const ban = await db
    .select({ ip: ipBans.ip })
    .from(ipBans)
    .where(eq(ipBans.ip, ip))
    .limit(1)
    .get();

  return !!ban;
};

// every address an account has signed in from, the ones an ip ban covers
const getLoginIpsForUser = async (userId: number): Promise<string[]> => {
  const rows = await db
    .selectDistinct({ ip: logins.ip })
    .from(logins)
    .where(eq(logins.userId, userId));

  return rows.flatMap(({ ip }) => (ip ? [ip] : []));
};

export { getLoginIpsForUser, isIpBanned };
