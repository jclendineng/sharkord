import { eq } from 'drizzle-orm';
import { db } from '../../db';
import { users } from '../../db/schema';
import { protectedProcedure } from '../../utils/trpc';

// the caller's own choice, invisible included, which nobody else is ever told
const getPresenceRoute = protectedProcedure.query(async ({ ctx }) => {
  const row = await db
    .select({ presence: users.presence, customStatus: users.customStatus })
    .from(users)
    .where(eq(users.id, ctx.userId))
    .limit(1)
    .get();

  return {
    presence: row?.presence ?? 'online',
    customStatus: row?.customStatus ?? null
  };
});

export { getPresenceRoute };
