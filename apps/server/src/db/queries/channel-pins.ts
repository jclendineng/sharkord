import { asc, eq } from 'drizzle-orm';
import { db } from '..';
import { channelPins } from '../schema';

// oldest pin first, the order the apps list them in
const getPinnedChannelIds = async (userId: number) => {
  const rows = await db
    .select({ channelId: channelPins.channelId })
    .from(channelPins)
    .where(eq(channelPins.userId, userId))
    .orderBy(asc(channelPins.createdAt))
    .all();

  return rows.map(({ channelId }) => channelId);
};

export { getPinnedChannelIds };
