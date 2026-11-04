import { and, eq, or } from 'drizzle-orm';
import { db } from '..';
import { directMessages, userBlocks } from '../schema';

// who the user blocked, as user ids
const getBlockedIds = async (userId: number): Promise<number[]> => {
  const rows = await db
    .select({ blockedId: userBlocks.blockedId })
    .from(userBlocks)
    .where(eq(userBlocks.blockerId, userId));

  return rows.map(({ blockedId }) => blockedId);
};

const isBlocked = async (blockerId: number, blockedId: number) => {
  const row = await db
    .select({ blockerId: userBlocks.blockerId })
    .from(userBlocks)
    .where(
      and(
        eq(userBlocks.blockerId, blockerId),
        eq(userBlocks.blockedId, blockedId)
      )
    )
    .limit(1)
    .get();

  return !!row;
};

// which way a block between two people goes: the user blocked them, they blocked the user,
// or nothing stands between them. a block both ways reads as the user's own
const getBlockBetween = async (
  userId: number,
  otherUserId: number
): Promise<'blocked' | 'blockedBy' | undefined> => {
  const rows = await db
    .select({ blockerId: userBlocks.blockerId })
    .from(userBlocks)
    .where(
      or(
        and(
          eq(userBlocks.blockerId, userId),
          eq(userBlocks.blockedId, otherUserId)
        ),
        and(
          eq(userBlocks.blockerId, otherUserId),
          eq(userBlocks.blockedId, userId)
        )
      )
    );

  if (rows.some(({ blockerId }) => blockerId === userId)) {
    return 'blocked';
  }

  return rows.length > 0 ? 'blockedBy' : undefined;
};

// the block standing in a one to one direct message, from the user's side. a group or a
// channel that is no direct message has none
const getDirectMessageBlock = async (channelId: number, userId: number) => {
  const pair = await db
    .select({
      userOneId: directMessages.userOneId,
      userTwoId: directMessages.userTwoId
    })
    .from(directMessages)
    .where(eq(directMessages.channelId, channelId))
    .limit(1)
    .get();

  if (!pair) {
    return undefined;
  }

  const otherUserId =
    pair.userOneId === userId ? pair.userTwoId : pair.userOneId;

  return getBlockBetween(userId, otherUserId);
};

export { getBlockBetween, getBlockedIds, getDirectMessageBlock, isBlocked };
