import { eq } from 'drizzle-orm';
import { db } from '../../db';
import { channelNotificationSettings } from '../../db/schema';
import { protectedProcedure } from '../../utils/trpc';

// only channels set away from the default have a row
const getChannelSettingsRoute = protectedProcedure.query(async ({ ctx }) =>
  db
    .select({
      channelId: channelNotificationSettings.channelId,
      level: channelNotificationSettings.level
    })
    .from(channelNotificationSettings)
    .where(eq(channelNotificationSettings.userId, ctx.userId))
);

export { getChannelSettingsRoute };
