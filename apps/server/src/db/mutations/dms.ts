import { and, eq } from 'drizzle-orm';
import { db } from '..';
import { directMessageClosures } from '../schema';

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

export { closeDirectMessage, reopenDirectMessage };
