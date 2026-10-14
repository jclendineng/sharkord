import { ServerEvents } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { acceptFriendRequest } from '../../db/mutations/friends';
import { getFriendship } from '../../db/queries/friends';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const acceptFriendRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.openDirectMessage.maxRequests,
  windowMs: config.rateLimiters.openDirectMessage.windowMs,
  logLabel: 'acceptFriend'
})
  .input(z.object({ userId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    const friendship = await getFriendship(ctx.userId, input.userId);

    // only a request they sent, one you sent waits on them
    invariant(
      friendship?.status === 'pending' &&
        friendship.requesterId === input.userId,
      {
        code: 'NOT_FOUND',
        message: 'There is no friend request from them.'
      }
    );

    await acceptFriendRequest(ctx.userId, input.userId);

    ctx.pubsub.publishFor(input.userId, ServerEvents.FRIENDSHIP_UPDATE, {
      userId: ctx.userId
    });
    ctx.pubsub.publishFor(ctx.userId, ServerEvents.FRIENDSHIP_UPDATE, {
      userId: input.userId
    });
  });

export { acceptFriendRoute };
