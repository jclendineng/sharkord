import { and, eq, gt, isNull, or } from 'drizzle-orm';
import { db } from '../../db';
import { channelNotificationSettings } from '../../db/schema';
import { protectedProcedure } from '../../utils/trpc';

// only channels set away from the default have a row. a mute that has run out is the default
// again, so it is left out
const getChannelSettingsRoute = protectedProcedure.query(async ({ ctx }) =>
  db
    .select({
      channelId: channelNotificationSettings.channelId,
      level: channelNotificationSettings.level,
      mutedUntil: channelNotificationSettings.mutedUntil
    })
    .from(channelNotificationSettings)
    .where(
      and(
        eq(channelNotificationSettings.userId, ctx.userId),
        or(
          isNull(channelNotificationSettings.mutedUntil),
          gt(channelNotificationSettings.mutedUntil, Date.now())
        )
      )
    )
);

export { getChannelSettingsRoute };
