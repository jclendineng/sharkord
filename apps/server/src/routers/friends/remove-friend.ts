import { ServerEvents } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { removeFriendship } from '../../db/mutations/friends';
import { getFriendship } from '../../db/queries/friends';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// unfriend, cancel a request you sent, or decline one you got
const removeFriendRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.openDirectMessage.maxRequests,
  windowMs: config.rateLimiters.openDirectMessage.windowMs,
  logLabel: 'removeFriend'
})
  .input(z.object({ userId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    const friendship = await getFriendship(ctx.userId, input.userId);

    invariant(friendship, {
      code: 'NOT_FOUND',
      message: "You're not friends."
    });

    await removeFriendship(ctx.userId, input.userId);

    ctx.pubsub.publishFor(input.userId, ServerEvents.FRIENDSHIP_UPDATE, {
      userId: ctx.userId
    });
    ctx.pubsub.publishFor(ctx.userId, ServerEvents.FRIENDSHIP_UPDATE, {
      userId: input.userId
    });
  });

export { removeFriendRoute };
