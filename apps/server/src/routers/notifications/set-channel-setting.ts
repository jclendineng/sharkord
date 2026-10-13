import { and, eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { channelNotificationSettings } from '../../db/schema';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// all: every message, mentions: the default, none: muted
const setChannelSettingRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.markAsRead.maxRequests,
  windowMs: config.rateLimiters.markAsRead.windowMs,
  logLabel: 'setChannelNotificationSetting'
})
  .input(
    z.object({
      channelId: z.number().int().positive(),
      level: z.enum(['all', 'mentions', 'none'])
    })
  )
  .mutation(async ({ ctx, input }) => {
    await assertChannelAccess(ctx, input.channelId);

    const where = and(
      eq(channelNotificationSettings.channelId, input.channelId),
      eq(channelNotificationSettings.userId, ctx.userId)
    );

    // the default is the absence of a row, so going back to it leaves nothing behind
    if (input.level === 'mentions') {
      await db.delete(channelNotificationSettings).where(where);
      return;
    }

    await db
      .insert(channelNotificationSettings)
      .values({
        userId: ctx.userId,
        channelId: input.channelId,
        level: input.level,
        updatedAt: Date.now()
      })
      .onConflictDoUpdate({
        target: [
          channelNotificationSettings.channelId,
          channelNotificationSettings.userId
        ],
        set: { level: input.level, updatedAt: Date.now() }
      });
  });

export { setChannelSettingRoute };
