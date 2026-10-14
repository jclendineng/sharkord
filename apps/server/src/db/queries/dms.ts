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
  groupDmMembers,
  groupDms,
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
  const [pairRows, groupRows] = await Promise.all([
    db
      .select({
        channelId: directMessages.channelId
      })
      .from(directMessages)
      .where(
        or(
          eq(directMessages.userOneId, userId),
          eq(directMessages.userTwoId, userId)
        )
      ),
    db
      .select({ channelId: groupDmMembers.channelId })
      .from(groupDmMembers)
      .where(eq(groupDmMembers.userId, userId))
  ]);

  return [...pairRows, ...groupRows].map((row) => row.channelId);
};

// a group conversation's details and everyone in it, for the groups the user is in
const getGroupDirectMessagesForUser = async (userId: number) => {
  const memberships = await db
    .select({ channelId: groupDmMembers.channelId })
    .from(groupDmMembers)
    .where(eq(groupDmMembers.userId, userId));

  const channelIds = memberships.map(({ channelId }) => channelId);

  if (channelIds.length === 0) {
    return [];
  }

  const [groups, members] = await Promise.all([
    db.select().from(groupDms).where(inArray(groupDms.channelId, channelIds)),
    db
      .select({
        channelId: groupDmMembers.channelId,
        userId: groupDmMembers.userId
      })
      .from(groupDmMembers)
      .where(inArray(groupDmMembers.channelId, channelIds))
  ]);

  return groups.map((group) => ({
    ...group,
    memberIds: members
      .filter((member) => member.channelId === group.channelId)
      .map((member) => member.userId)
  }));
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
  const [pairRows, groupRows] = await Promise.all([
    db
      .select()
      .from(directMessages)
      .where(
        or(
          eq(directMessages.userOneId, userId),
          eq(directMessages.userTwoId, userId)
        )
      ),
    getGroupDirectMessagesForUser(userId)
  ]);

  // one shape for both: a group shows as one of its other members, with the group alongside
  const rows = [
    ...pairRows.map((row) => ({
      channelId: row.channelId,
      otherUserId: row.userOneId === userId ? row.userTwoId : row.userOneId,
      createdAt: row.createdAt,
      group: null
    })),
    ...groupRows.map((row) => {
      const memberIds = row.memberIds.filter((id) => id !== userId);

      return {
        channelId: row.channelId,
        otherUserId: memberIds[0] ?? userId,
        createdAt: row.createdAt,
        group: { name: row.name, memberIds }
      };
    })
  ];

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
      const lastMessageAt = lastMessageMap.get(row.channelId) ?? row.createdAt;

      return {
        channelId: row.channelId,
        userId: row.otherUserId,
        group: row.group,
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
  const [dm, groupMember] = await Promise.all([
    db
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
      .get(),
    db
      .select({ channelId: groupDmMembers.channelId })
      .from(groupDmMembers)
      .where(
        and(
          eq(groupDmMembers.channelId, channelId),
          eq(groupDmMembers.userId, userId)
        )
      )
      .limit(1)
      .get()
  ]);

  return !!dm || !!groupMember;
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

  if (dm) {
    return [dm.userOneId, dm.userTwoId];
  }

  // a group's members
  const members = await db
    .select({ userId: groupDmMembers.userId })
    .from(groupDmMembers)
    .where(eq(groupDmMembers.channelId, channelId));

  return members.map(({ userId }) => userId);
};

export {
  assertDmChannel,
  getDirectMessageChannel,
  getDirectMessageChannelIdsForUser,
  getDirectMessageChannelParticipantIds,
  getDirectMessageConversations,
  getGroupDirectMessagesForUser,
  isDirectMessageChannel,
  isUserDmParticipant,
  normalizePair
};
