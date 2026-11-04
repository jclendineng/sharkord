import { ServerEvents } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { removeBlock } from '../../db/mutations/blocks';
import { isBlocked } from '../../db/queries/blocks';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const unblockUserRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.openDirectMessage.maxRequests,
  windowMs: config.rateLimiters.openDirectMessage.windowMs,
  logLabel: 'unblockUser'
})
  .input(z.object({ userId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    const blocked = await isBlocked(ctx.userId, input.userId);

    invariant(blocked, {
      code: 'NOT_FOUND',
      message: "You haven't blocked this person."
    });

    await removeBlock(ctx.userId, input.userId);

    ctx.pubsub.publishFor(ctx.userId, ServerEvents.FRIENDSHIP_UPDATE, {
      userId: input.userId
    });
  });

export { unblockUserRoute };
