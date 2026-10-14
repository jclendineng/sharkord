import {
  getPlainTextFromHtml,
  type TDirectMessageConversation
} from '@sharkord/shared';
import { TRPCError } from '@trpc/server';
import { and, eq, inArray, max, or, sql } from 'drizzle-orm';
import { db } from '..';
import {
  channels,
  directMessageClosures,
  directMessages,
  messages
} from '../schema';
import { getChannelsReadStatesForUser } from './channels';
import { getSettings } from './server';

const normalizePair = (a: number, b: number): [number, number] =>
  a < b ? [a, b] : [b, a];

// returns the DM channel between the two users
const getDirectMessageChannel = async (
  userOneId: number,
  userTwoId: number
) => {
  const [a, b] = normalizePair(userOneId, userTwoId);

  return db
    .select()
    .from(directMessages)
    .where(
      and(eq(directMessages.userOneId, a), eq(directMessages.userTwoId, b))
    )
    .limit(1)
    .get();
};

// returns all DM channel IDs the user is a participant in
const getDirectMessageChannelIdsForUser = async (
  userId: number
): Promise<number[]> => {
  const rows = await db
    .select({
      channelId: directMessages.channelId
    })
    .from(directMessages)
    .where(
      or(
        eq(directMessages.userOneId, userId),
        eq(directMessages.userTwoId, userId)
      )
    );

  return rows.map((row) => row.channelId);
};

// returns all DM channels the user is a participant in along with metadata
const PREVIEW_LENGTH = 120;

// one line of plain text, short enough for a row
const preview = (content: string | null | undefined): string | null => {
  if (content === undefined) {
    return null;
  }

  const text = getPlainTextFromHtml(content ?? '')
    .replace(/\s+/g, ' ')
    .trim();

  return text.slice(0, PREVIEW_LENGTH);
};

const getDirectMessageConversations = async (
  userId: number
): Promise<TDirectMessageConversation[]> => {
  const rows = await db
    .select()
    .from(directMessages)
    .where(
      or(
        eq(directMessages.userOneId, userId),
        eq(directMessages.userTwoId, userId)
      )
    );

  if (rows.length === 0) {
    return [];
  }

  const channelIds = rows.map((row) => row.channelId);

  const ids = sql.join(
    channelIds.map((id) => sql`${id}`),
    sql`, `
  );

  const [lastMessageRows, unreadMapRaw, closures, newestRows] =
    await Promise.all([
      db
        .select({
          channelId: messages.channelId,
          lastMessageAt: max(messages.createdAt)
        })
        .from(messages)
        .where(inArray(messages.channelId, channelIds))
        .groupBy(messages.channelId),
      getChannelsReadStatesForUser(userId),
      db
        .select({
          channelId: directMessageClosures.channelId,
          closedAt: directMessageClosures.closedAt
        })
        .from(directMessageClosures)
        .where(eq(directMessageClosures.userId, userId)),
      // the newest message of each conversation, for its preview in the list
      db.all<{
        channelId: number;
        userId: number | null;
        content: string | null;
      }>(sql`
      SELECT m.channel_id AS channelId, m.user_id AS userId, m.content AS content
      FROM messages m
      JOIN (
        SELECT channel_id, MAX(created_at) AS newest
        FROM messages
        WHERE channel_id IN (${ids}) AND parent_message_id IS NULL
        GROUP BY channel_id
      ) latest ON latest.channel_id = m.channel_id AND latest.newest = m.created_at
      WHERE m.parent_message_id IS NULL
    `)
    ]);

  const newestByChannel = new Map(
    newestRows.map((row) => [row.channelId, row])
  );

  const closedAtMap = new Map(
    closures.map(({ channelId, closedAt }) => [channelId, closedAt])
  );

  const lastMessageMap = new Map<number, number>();

  for (const row of lastMessageRows) {
    lastMessageMap.set(row.channelId, row.lastMessageAt ?? 0);
  }

  const conversations = rows
    .map((row) => {
      const otherUserId =
        row.userOneId === userId ? row.userTwoId : row.userOneId;
      const lastMessageAt = lastMessageMap.get(row.channelId) ?? row.createdAt;

      return {
        channelId: row.channelId,
        userId: otherUserId,
        unreadCount: unreadMapRaw[row.channelId] ?? 0,
        lastMessageAt,
        lastMessagePreview: preview(
          newestByChannel.get(row.channelId)?.content
        ),
        lastMessageUserId: newestByChannel.get(row.channelId)?.userId ?? null
      };
    })
    // a closed conversation comes back with the first message after it was closed
    .filter(
      ({ channelId, lastMessageAt }) =>
        lastMessageAt > (closedAtMap.get(channelId) ?? -1)
    );

  conversations.sort((a, b) => b.lastMessageAt - a.lastMessageAt);

  return conversations;
};

// checks if a channel is a DM channel by looking for it in the directMessages table
const isDirectMessageChannel = async (channelId: number): Promise<boolean> => {
  const channel = await db
    .select({ isDm: channels.isDm })
    .from(channels)
    .where(eq(channels.id, channelId))
    .limit(1)
    .get();

  return !!channel?.isDm;
};

// checks if the user is a participant in the DM channel by looking for a matching row in the directMessages table
const isUserDmParticipant = async (
  channelId: number,
  userId: number
): Promise<boolean> => {
  const dm = await db
    .select({ channelId: directMessages.channelId })
    .from(directMessages)
    .where(
      and(
        eq(directMessages.channelId, channelId),
        or(
          eq(directMessages.userOneId, userId),
          eq(directMessages.userTwoId, userId)
        )
      )
    )
    .limit(1)
    .get();

  return !!dm;
};

// checks if the channel is a DM channel, and if so that direct messages are on
// and the user is a participant. returns whether it was a DM so the caller does
// not have to ask the same question again
const assertDmChannel = async (
  channelId: number,
  userId: number
): Promise<boolean> => {
  const isDm = await isDirectMessageChannel(channelId);

  if (!isDm) return false;

  const settings = await getSettings();

  if (!settings.directMessagesEnabled) {
    throw new TRPCError({
      code: 'FORBIDDEN',
      message: 'Direct messages are disabled on this server'
    });
  }

  const isParticipant = await isUserDmParticipant(channelId, userId);

  if (!isParticipant) {
    throw new TRPCError({
      code: 'FORBIDDEN',
      message: 'You are not a participant in this DM channel'
    });
  }

  return true;
};

const getDirectMessageChannelParticipantIds = async (
  channelId: number
): Promise<number[]> => {
  const dm = await db
    .select({
      userOneId: directMessages.userOneId,
      userTwoId: directMessages.userTwoId
    })
    .from(directMessages)
    .where(eq(directMessages.channelId, channelId))
    .limit(1)
    .get();

  if (!dm) return [];

  return [dm.userOneId, dm.userTwoId];
};

export {
  assertDmChannel,
  getDirectMessageChannel,
  getDirectMessageChannelIdsForUser,
  getDirectMessageChannelParticipantIds,
  getDirectMessageConversations,
  isDirectMessageChannel,
  isUserDmParticipant,
  normalizePair
};
