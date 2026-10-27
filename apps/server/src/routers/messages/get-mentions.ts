import {
  hasMention,
  zMessagesCursor,
  type TMessagesCursor
} from '@sharkord/shared';
import {
  and,
  desc,
  eq,
  gt,
  inArray,
  isNull,
  lt,
  ne,
  or,
  sql
} from 'drizzle-orm';
import { alias } from 'drizzle-orm/sqlite-core';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { getChannelsForUser } from '../../db/queries/channels';
import { joinMessagesWithRelations } from '../../db/queries/messages';
import { getUserRoleIds } from '../../db/queries/roles';
import { channelReadStates, messages } from '../../db/schema';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const MENTIONS_LIMIT = 25;

// the caller's inbox: messages that mention them or one of their roles, and replies to their
// own messages, newest first. the same set push notifications go out for, minus direct
// messages, which have a list of their own. a mention the channel has been read past is
// done with and drops out, the same line the unread count draws
const getMentionsRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.getMessages.maxRequests,
  windowMs: config.rateLimiters.getMessages.windowMs,
  logLabel: 'getMentions'
})
  .input(
    z.object({
      cursor: zMessagesCursor.nullish()
    })
  )
  .query(async ({ ctx, input }) => {
    const [accessibleChannels, roleIds] = await Promise.all([
      getChannelsForUser(ctx.userId),
      getUserRoleIds(ctx.userId)
    ]);

    const channelIds = accessibleChannels.map(({ id }) => id);

    if (channelIds.length === 0) {
      return { messages: [], nextCursor: null };
    }

    const repliedTo = alias(messages, 'replied_to');
    const { cursor } = input;

    // the globs only narrow the rows down in sql, hasMention below decides, so a stray
    // data-user-id attribute outside a mention span is not enough to land in the inbox
    const rows = await db
      .select({ message: messages, repliedToUserId: repliedTo.userId })
      .from(messages)
      .leftJoin(repliedTo, eq(repliedTo.id, messages.replyToMessageId))
      .leftJoin(
        channelReadStates,
        and(
          eq(channelReadStates.channelId, messages.channelId),
          eq(channelReadStates.userId, ctx.userId)
        )
      )
      .where(
        and(
          inArray(messages.channelId, channelIds),
          or(
            isNull(channelReadStates.lastReadMessageId),
            gt(messages.id, channelReadStates.lastReadMessageId)
          ),
          or(isNull(messages.userId), ne(messages.userId, ctx.userId)),
          or(
            sql`${messages.content} GLOB ${`*data-user-id="${ctx.userId}"*`}`,
            ...roleIds.map(
              (roleId) =>
                sql`${messages.content} GLOB ${`*data-role-id="${roleId}"*`}`
            ),
            eq(repliedTo.userId, ctx.userId)
          ),
          cursor
            ? or(
                lt(messages.createdAt, cursor.createdAt),
                and(
                  eq(messages.createdAt, cursor.createdAt),
                  lt(messages.id, cursor.id)
                )
              )
            : undefined
        )
      )
      .orderBy(desc(messages.createdAt), desc(messages.id))
      .limit(MENTIONS_LIMIT + 1);

    let nextCursor: TMessagesCursor | null = null;

    // paged on the rows sql returned, not on what survives the filter, so a page that loses
    // rows to hasMention still continues from the right place
    if (rows.length > MENTIONS_LIMIT) {
      rows.pop();

      const last = rows.at(-1);

      nextCursor = last
        ? { createdAt: last.message.createdAt, id: last.message.id }
        : null;
    }

    const mentions = rows
      .filter(
        ({ message, repliedToUserId }) =>
          repliedToUserId === ctx.userId ||
          hasMention(message.content, ctx.userId, roleIds)
      )
      .map(({ message }) => message);

    return {
      messages: await joinMessagesWithRelations(mentions),
      nextCursor
    };
  });

export { getMentionsRoute };
