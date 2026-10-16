import { and, count, desc, eq, inArray, isNotNull, max } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { joinMessagesWithRelations } from '../../db/queries/messages';
import { messages } from '../../db/schema';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// discord's threads list keeps to the busiest, there is no paging through every thread
const THREADS_LIMIT = 50;

// a channel's threads, the messages that have replies, the one replied to last first
const getThreadsRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.getMessages.maxRequests,
  windowMs: config.rateLimiters.getMessages.windowMs,
  logLabel: 'getThreads'
})
  .input(
    z.object({
      channelId: z.number().int().positive()
    })
  )
  .query(async ({ ctx, input }) => {
    await assertChannelAccess(ctx, input.channelId);

    const lastReplyAt = max(messages.createdAt);

    const threads = await db
      .select({
        parentMessageId: messages.parentMessageId,
        replyCount: count(),
        lastReplyAt
      })
      .from(messages)
      .where(
        and(
          eq(messages.channelId, input.channelId),
          isNotNull(messages.parentMessageId)
        )
      )
      .groupBy(messages.parentMessageId)
      // replies sent in the same millisecond fall back to the later one written
      .orderBy(desc(lastReplyAt), desc(max(messages.id)))
      .limit(THREADS_LIMIT);

    const parentIds = threads
      .map((thread) => thread.parentMessageId)
      .filter((id): id is number => id !== null);

    if (parentIds.length === 0) {
      return [];
    }

    const parentRows = await db
      .select()
      .from(messages)
      .where(inArray(messages.id, parentIds));

    const parents = await joinMessagesWithRelations(parentRows);
    const parentsById = new Map(parents.map((parent) => [parent.id, parent]));

    return threads.flatMap((thread) => {
      const parent = thread.parentMessageId
        ? parentsById.get(thread.parentMessageId)
        : undefined;

      if (!parent) {
        return [];
      }

      return [
        {
          ...parent,
          replyCount: thread.replyCount,
          lastReplyAt: thread.lastReplyAt ?? parent.createdAt
        }
      ];
    });
  });

export { getThreadsRoute };
