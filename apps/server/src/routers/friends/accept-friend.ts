import { ServerEvents } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { acceptFriendRequest } from '../../db/mutations/friends';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const acceptFriendRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.openDirectMessage.maxRequests,
  windowMs: config.rateLimiters.openDirectMessage.windowMs,
  logLabel: 'acceptFriend'
})
  .input(z.object({ userId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    const isAccepted = await acceptFriendRequest(ctx.userId, input.userId);

    invariant(isAccepted, {
      code: 'NOT_FOUND',
      message: 'There is no friend request from them.'
    });

    ctx.pubsub.publishFor(input.userId, ServerEvents.FRIENDSHIP_UPDATE, {
      userId: ctx.userId
    });
    ctx.pubsub.publishFor(ctx.userId, ServerEvents.FRIENDSHIP_UPDATE, {
      userId: input.userId
    });
  });

export { acceptFriendRoute };
