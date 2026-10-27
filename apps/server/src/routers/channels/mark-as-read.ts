import { ServerEvents } from '@sharkord/shared';
import { desc, eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { getChannelsReadStatesForUser } from '../../db/queries/channels';
import { channelReadStates, messages } from '../../db/schema';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const markAsReadRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.markAsRead.maxRequests,
  windowMs: config.rateLimiters.markAsRead.windowMs,
  logLabel: 'markAsRead'
})
  .input(
    z.object({
      channelId: z.number()
    })
  )
  .mutation(async ({ ctx, input }) => {
    await assertChannelAccess(ctx, input.channelId);

    const { channelId } = input;

    // thread replies count too, so reading the channel clears the inbox's mentions in its
    // threads as well. the unread count only looks at the channel's own messages, and ids
    // only grow, so a marker on a reply still splits those in the right place
    const newestMessage = await db
      .select({ id: messages.id })
      .from(messages)
      .where(eq(messages.channelId, channelId))
      .orderBy(desc(messages.id))
      .limit(1)
      .get();

    if (!newestMessage) {
      return;
    }

    await db
      .insert(channelReadStates)
      .values({
        channelId,
        userId: ctx.userId,
        lastReadMessageId: newestMessage.id,
        lastReadAt: Date.now()
      })
      .onConflictDoUpdate({
        target: [channelReadStates.channelId, channelReadStates.userId],
        set: {
          lastReadMessageId: newestMessage.id,
          lastReadAt: Date.now()
        }
      });

    const updatedReadStates = await getChannelsReadStatesForUser(
      ctx.userId,
      channelId
    );

    // the caller's other sessions need to drop the unread badge too
    ctx.pubsub.publishFor(ctx.userId, ServerEvents.CHANNEL_READ_STATES_UPDATE, {
      channelId,
      count: updatedReadStates[channelId] ?? 0
    });
  });

export { markAsReadRoute };
