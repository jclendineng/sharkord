import type { TFriendLists } from '@sharkord/shared';
import { and, eq, or } from 'drizzle-orm';
import { db } from '..';
import { friendships } from '../schema';
import { normalizePair } from './dms';

const getFriendship = async (userId: number, otherUserId: number) => {
  const [userOneId, userTwoId] = normalizePair(userId, otherUserId);

  return db
    .select()
    .from(friendships)
    .where(
      and(
        eq(friendships.userOneId, userOneId),
        eq(friendships.userTwoId, userTwoId)
      )
    )
    .limit(1)
    .get();
};

const getFriendLists = async (userId: number): Promise<TFriendLists> => {
  const rows = await db
    .select({
      userOneId: friendships.userOneId,
      userTwoId: friendships.userTwoId,
      requesterId: friendships.requesterId,
      status: friendships.status
    })
    .from(friendships)
    .where(
      or(eq(friendships.userOneId, userId), eq(friendships.userTwoId, userId))
    );

  const lists: TFriendLists = { friends: [], incoming: [], outgoing: [] };

  for (const row of rows) {
    const otherUserId =
      row.userOneId === userId ? row.userTwoId : row.userOneId;

    if (row.status === 'accepted') {
      lists.friends.push(otherUserId);
    } else if (row.requesterId === userId) {
      lists.outgoing.push(otherUserId);
    } else {
      lists.incoming.push(otherUserId);
    }
  }

  return lists;
};

// which of these people are the user's friends, a group can only be made of friends
const getFriendIds = async (userId: number): Promise<Set<number>> => {
  const { friends } = await getFriendLists(userId);

  return new Set(friends);
};

export { getFriendIds, getFriendLists, getFriendship };
