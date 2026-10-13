import { ServerEvents } from '@sharkord/shared';
import { and, desc, eq, isNull, lt } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { getChannelsReadStatesForUser } from '../../db/queries/channels';
import { channelReadStates, messages } from '../../db/schema';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// discord's "mark unread": the channel reads as unread from this message on
const markAsUnreadRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.markAsRead.maxRequests,
  windowMs: config.rateLimiters.markAsRead.windowMs,
  logLabel: 'markAsUnread'
})
  .input(
    z.object({
      messageId: z.number().int().positive()
    })
  )
  .mutation(async ({ ctx, input }) => {
    const message = await db
      .select({
        id: messages.id,
        channelId: messages.channelId,
        parentMessageId: messages.parentMessageId
      })
      .from(messages)
      .where(eq(messages.id, input.messageId))
      .limit(1)
      .get();

    invariant(message, {
      code: 'NOT_FOUND',
      message: 'Message not found'
    });

    await assertChannelAccess(ctx, message.channelId);

    // read state only counts a channel's own messages, not replies inside a thread
    invariant(!message.parentMessageId, {
      code: 'BAD_REQUEST',
      message: 'Only a message in the channel itself can be marked unread.'
    });

    const previous = await db
      .select({ id: messages.id })
      .from(messages)
      .where(
        and(
          eq(messages.channelId, message.channelId),
          isNull(messages.parentMessageId),
          lt(messages.id, message.id)
        )
      )
      .orderBy(desc(messages.id))
      .limit(1)
      .get();

    const lastReadMessageId = previous?.id ?? null;

    await db
      .insert(channelReadStates)
      .values({
        channelId: message.channelId,
        userId: ctx.userId,
        lastReadMessageId,
        lastReadAt: Date.now()
      })
      .onConflictDoUpdate({
        target: [channelReadStates.channelId, channelReadStates.userId],
        set: { lastReadMessageId, lastReadAt: Date.now() }
      });

    const readStates = await getChannelsReadStatesForUser(
      ctx.userId,
      message.channelId
    );

    // the caller's other sessions show the badge again too
    ctx.pubsub.publishFor(ctx.userId, ServerEvents.CHANNEL_READ_STATES_UPDATE, {
      channelId: message.channelId,
      count: readStates[message.channelId] ?? 0
    });
  });

export { markAsUnreadRoute };
