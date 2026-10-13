import { ServerEvents } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { getPublicUserById } from '../../db/queries/users';
import { users } from '../../db/schema';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';
import { getUserStatus, setUserPresence } from '../../utils/wss';

const CUSTOM_STATUS_MAX_LENGTH = 128;

// the caller's availability and status message, everyone sees the result straight away
const setPresenceRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.markAsRead.maxRequests,
  windowMs: config.rateLimiters.markAsRead.windowMs,
  logLabel: 'setPresence'
})
  .input(
    z.object({
      presence: z.enum(['online', 'idle', 'dnd', 'invisible']),
      customStatus: z.string().trim().max(CUSTOM_STATUS_MAX_LENGTH).nullable()
    })
  )
  .mutation(async ({ ctx, input }) => {
    // an empty message clears it
    const customStatus = input.customStatus || null;

    await db
      .update(users)
      .set({ presence: input.presence, customStatus })
      .where(eq(users.id, ctx.userId));

    setUserPresence(ctx.userId, input.presence);

    const user = await getPublicUserById(ctx.userId);

    if (user) {
      ctx.pubsub.publish(ServerEvents.USER_UPDATE, {
        ...user,
        status: getUserStatus(ctx.userId)
      });
    }
  });

export { setPresenceRoute };
