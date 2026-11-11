import { and, desc, eq } from 'drizzle-orm';
import { db } from '..';
import { sessions } from '../schema';

const getSession = async (sessionId: string, userId: number) =>
  db
    .select({ id: sessions.id })
    .from(sessions)
    .where(and(eq(sessions.id, sessionId), eq(sessions.userId, userId)))
    .limit(1)
    .get();

// every device still signed in, most recently used first
const getActiveSessions = async (userId: number) =>
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
    .where(eq(sessions.userId, userId))
    .orderBy(desc(sessions.lastActiveAt));

export { getActiveSessions, getSession };
