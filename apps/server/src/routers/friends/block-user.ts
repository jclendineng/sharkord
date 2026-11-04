import { ServerEvents } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { addBlock } from '../../db/mutations/blocks';
import { getFriendship } from '../../db/queries/friends';
import { users } from '../../db/schema';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// blocks someone, ending any friendship or request between the two. blocking twice changes
// nothing. the blocked user is not told, they only see a friendship that is gone
const blockUserRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.openDirectMessage.maxRequests,
  windowMs: config.rateLimiters.openDirectMessage.windowMs,
  logLabel: 'blockUser'
})
  .input(z.object({ userId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    invariant(input.userId !== ctx.userId, {
      code: 'BAD_REQUEST',
      message: "You can't block yourself."
    });

    const target = await db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.id, input.userId))
      .limit(1)
      .get();

    invariant(target, {
      code: 'NOT_FOUND',
      message: 'User not found'
    });

    const friendship = await getFriendship(ctx.userId, input.userId);

    addBlock(ctx.userId, input.userId);

    if (friendship) {
      ctx.pubsub.publishFor(input.userId, ServerEvents.FRIENDSHIP_UPDATE, {
        userId: ctx.userId
      });
    }

    // the user's other devices fetch the list again, the blocked list with it
    ctx.pubsub.publishFor(ctx.userId, ServerEvents.FRIENDSHIP_UPDATE, {
      userId: input.userId
    });
  });

export { blockUserRoute };
