import { eq } from 'drizzle-orm';
import { db } from '../../db';
import { users } from '../../db/schema';
import { protectedProcedure } from '../../utils/trpc';

const getPrivacyRoute = protectedProcedure.query(async ({ ctx }) => {
  const row = await db
    .select({ allowDirectMessages: users.allowDirectMessages })
    .from(users)
    .where(eq(users.id, ctx.userId))
    .limit(1)
    .get();

  return { allowDirectMessages: row?.allowDirectMessages ?? true };
});

export { getPrivacyRoute };
