import { ServerEvents } from '@sharkord/shared';
import { and, eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { getPinnedChannelIds } from '../../db/queries/channel-pins';
import { channelPins } from '../../db/schema';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const setPinnedRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.markAsRead.maxRequests,
  windowMs: config.rateLimiters.markAsRead.windowMs,
  logLabel: 'setChannelPinned'
})
  .input(
    z.object({
      channelId: z.number().int().positive(),
      pinned: z.boolean()
    })
  )
  .mutation(async ({ ctx, input }) => {
    await assertChannelAccess(ctx, input.channelId);

    if (input.pinned) {
      // pinning one already pinned keeps its place
      await db
        .insert(channelPins)
        .values({
          userId: ctx.userId,
          channelId: input.channelId,
          createdAt: Date.now()
        })
        .onConflictDoNothing();
    } else {
      await db
        .delete(channelPins)
        .where(
          and(
            eq(channelPins.userId, ctx.userId),
            eq(channelPins.channelId, input.channelId)
          )
        );
    }

    // the account's other devices move the channel too
    ctx.pubsub.publishFor(
      ctx.userId,
      ServerEvents.CHANNEL_PINS_UPDATE,
      await getPinnedChannelIds(ctx.userId)
    );
  });

export { setPinnedRoute };
