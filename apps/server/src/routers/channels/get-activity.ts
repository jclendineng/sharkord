import { and, inArray, isNull, max } from 'drizzle-orm';
import { config } from '../../config';
import { db } from '../../db';
import { getChannelsForUser } from '../../db/queries/channels';
import { messages } from '../../db/schema';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// when each server channel the caller can see last had a message, for the "active 5m ago"
// under the channels search suggests. thread replies are left out, as on discord
const getActivityRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.getMessages.maxRequests,
  windowMs: config.rateLimiters.getMessages.windowMs,
  logLabel: 'getActivity'
}).query(async ({ ctx }) => {
  const accessibleChannels = await getChannelsForUser(ctx.userId);

  const channelIds = accessibleChannels
    .filter((channel) => !channel.isDm)
    .map((channel) => channel.id);

  if (channelIds.length === 0) {
    return [];
  }

  const rows = await db
    .select({
      channelId: messages.channelId,
      lastMessageAt: max(messages.createdAt)
    })
    .from(messages)
    .where(
      and(
        inArray(messages.channelId, channelIds),
        isNull(messages.parentMessageId)
      )
    )
    .groupBy(messages.channelId);

  return rows.flatMap(({ channelId, lastMessageAt }) =>
    lastMessageAt === null ? [] : [{ channelId, lastMessageAt }]
  );
});

export { getActivityRoute };
