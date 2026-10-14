import { ChannelType } from '@sharkord/shared';
import { and, eq } from 'drizzle-orm';
import { db } from '..';
import {
  channels,
  directMessageClosures,
  groupDmMembers,
  groupDms
} from '../schema';

// hides the conversation from this participant's list, see directMessageClosures
const closeDirectMessage = async (channelId: number, userId: number) => {
  const closedAt = Date.now();

  await db
    .insert(directMessageClosures)
    .values({ channelId, userId, closedAt })
    .onConflictDoUpdate({
      target: [directMessageClosures.channelId, directMessageClosures.userId],
      set: { closedAt }
    });
};

// opening it again, from a profile or the new message list, brings it back straight away
const reopenDirectMessage = async (channelId: number, userId: number) => {
  await db
    .delete(directMessageClosures)
    .where(
      and(
        eq(directMessageClosures.channelId, channelId),
        eq(directMessageClosures.userId, userId)
      )
    );
};

// a group's channel, its details and its members in one go
const createGroupDirectMessage = (
  ownerId: number,
  memberIds: number[],
  name: string | null
) => {
  const now = Date.now();

  return db.transaction((tx) => {
    const channel = tx
      .insert(channels)
      .values({
        // as a two person dm, voice so the group can call later
        type: ChannelType.VOICE,
        name: `Group DM - ${ownerId}`,
        topic: null,
        private: true,
        isDm: true,
        position: 0,
        categoryId: null,
        createdAt: now
      })
      .returning()
      .get();

    tx.insert(groupDms)
      .values({ channelId: channel.id, name, ownerId, createdAt: now })
      .run();

    tx.insert(groupDmMembers)
      .values(
        memberIds.map((userId) => ({
          channelId: channel.id,
          userId,
          addedAt: now
        }))
      )
      .run();

    return channel;
  });
};

const addGroupDirectMessageMembers = async (
  channelId: number,
  userIds: number[]
) => {
  const now = Date.now();

  await db
    .insert(groupDmMembers)
    .values(userIds.map((userId) => ({ channelId, userId, addedAt: now })))
    .onConflictDoNothing();
};

// the last one out takes the conversation with them, the channel cascades the rest
const leaveGroupDirectMessage = (channelId: number, userId: number) =>
  db.transaction((tx) => {
    tx.delete(groupDmMembers)
      .where(
        and(
          eq(groupDmMembers.channelId, channelId),
          eq(groupDmMembers.userId, userId)
        )
      )
      .run();

    const remaining = tx
      .select({ userId: groupDmMembers.userId })
      .from(groupDmMembers)
      .where(eq(groupDmMembers.channelId, channelId))
      .all();

    if (remaining.length === 0) {
      tx.delete(channels).where(eq(channels.id, channelId)).run();
    }

    return remaining.map((row) => row.userId);
  });

const renameGroupDirectMessage = async (
  channelId: number,
  name: string | null
) => {
  await db
    .update(groupDms)
    .set({ name })
    .where(eq(groupDms.channelId, channelId));
};

export {
  addGroupDirectMessageMembers,
  closeDirectMessage,
  createGroupDirectMessage,
  leaveGroupDirectMessage,
  renameGroupDirectMessage,
  reopenDirectMessage
};
