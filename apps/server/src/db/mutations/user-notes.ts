import { and, eq } from 'drizzle-orm';
import { db } from '..';
import { userNotes } from '../schema';

// an empty note removes it rather than keeping an empty row
const setUserNote = async (
  userId: number,
  targetUserId: number,
  note: string
) => {
  if (!note) {
    await db
      .delete(userNotes)
      .where(
        and(
          eq(userNotes.userId, userId),
          eq(userNotes.targetUserId, targetUserId)
        )
      );

    return;
  }

  const updatedAt = Date.now();

  await db
    .insert(userNotes)
    .values({ userId, targetUserId, note, updatedAt })
    .onConflictDoUpdate({
      target: [userNotes.userId, userNotes.targetUserId],
      set: { note, updatedAt }
    });
};

export { setUserNote };
