import { and, eq } from 'drizzle-orm';
import { db } from '..';
import { normalizePair } from '../queries/dms';
import { friendships } from '../schema';

const pairWhere = (userId: number, otherUserId: number) => {
  const [userOneId, userTwoId] = normalizePair(userId, otherUserId);

  return and(
    eq(friendships.userOneId, userOneId),
    eq(friendships.userTwoId, userTwoId)
  );
};

const addFriendRequest = async (requesterId: number, addresseeId: number) => {
  const [userOneId, userTwoId] = normalizePair(requesterId, addresseeId);

  await db.insert(friendships).values({
    userOneId,
    userTwoId,
    requesterId,
    status: 'pending',
    createdAt: Date.now()
  });
};

const acceptFriendRequest = async (userId: number, otherUserId: number) => {
  await db
    .update(friendships)
    .set({ status: 'accepted', acceptedAt: Date.now() })
    .where(pairWhere(userId, otherUserId));
};

// unfriends, cancels a request sent or declines one received alike
const removeFriendship = async (userId: number, otherUserId: number) => {
  await db.delete(friendships).where(pairWhere(userId, otherUserId));
};

export { acceptFriendRequest, addFriendRequest, removeFriendship };
