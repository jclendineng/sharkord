import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { users } from '../../db/schema';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// the caller's own choices about who can reach them
const updatePrivacyRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.markAsRead.maxRequests,
  windowMs: config.rateLimiters.markAsRead.windowMs,
  logLabel: 'updatePrivacy'
})
  .input(
    z.object({
      allowDirectMessages: z.boolean()
    })
  )
  .mutation(async ({ ctx, input }) => {
    await db
      .update(users)
      .set({ allowDirectMessages: input.allowDirectMessages })
      .where(eq(users.id, ctx.userId));
  });

export { updatePrivacyRoute };
