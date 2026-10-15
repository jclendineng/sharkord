import { and, eq } from 'drizzle-orm';
import { db } from '..';
import { userNotes } from '../schema';

// the caller's own note on someone, empty when they have none
const getUserNote = async (userId: number, targetUserId: number) => {
  const row = await db
    .select({ note: userNotes.note })
    .from(userNotes)
    .where(
      and(
        eq(userNotes.userId, userId),
        eq(userNotes.targetUserId, targetUserId)
      )
    )
    .limit(1)
    .get();

  return row?.note ?? '';
};

export { getUserNote };
