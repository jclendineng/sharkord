import { and, desc, eq, gt } from 'drizzle-orm';
import { db } from '..';
import { sessions } from '../schema';

const getSession = async (sessionId: string, userId: number) =>
  db
    .select({ id: sessions.id })
    .from(sessions)
    .where(and(eq(sessions.id, sessionId), eq(sessions.userId, userId)))
    .limit(1)
    .get();

// a session idle for longer than its token lives cannot be used any more, so it is left out
const getActiveSessions = async (userId: number, activeSince: number) =>
  db
    .select({
      id: sessions.id,
      os: sessions.os,
      device: sessions.device,
      ip: sessions.ip,
      city: sessions.city,
      region: sessions.region,
      country: sessions.country,
      createdAt: sessions.createdAt,
      lastActiveAt: sessions.lastActiveAt
    })
    .from(sessions)
    .where(
      and(eq(sessions.userId, userId), gt(sessions.lastActiveAt, activeSince))
    )
    .orderBy(desc(sessions.lastActiveAt));

export { getActiveSessions, getSession };
