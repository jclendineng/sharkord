import { and, eq } from 'drizzle-orm';
import { db } from '..';
import { normalizePair } from '../queries/dms';
import { friendships, userBlocks } from '../schema';

// a block ends a friendship or a request either way, in the same write
const addBlock = (blockerId: number, blockedId: number) => {
  const [userOneId, userTwoId] = normalizePair(blockerId, blockedId);

  db.transaction((tx) => {
    tx.insert(userBlocks)
      .values({ blockerId, blockedId, createdAt: Date.now() })
      .onConflictDoNothing()
      .run();

    tx.delete(friendships)
      .where(
        and(
          eq(friendships.userOneId, userOneId),
          eq(friendships.userTwoId, userTwoId)
        )
      )
      .run();
  });
};

const removeBlock = async (blockerId: number, blockedId: number) => {
  await db
    .delete(userBlocks)
    .where(
      and(
        eq(userBlocks.blockerId, blockerId),
        eq(userBlocks.blockedId, blockedId)
      )
    );
};

export { addBlock, removeBlock };
