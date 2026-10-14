import { and, eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { channelNotificationSettings } from '../../db/schema';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// all: every message, mentions: the default, none: muted. a mute may last a while, as discord's
// "for 1 hour", after which the channel is back to the default
const MAX_MUTE_MINUTES = 60 * 24 * 30;

const setChannelSettingRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.markAsRead.maxRequests,
  windowMs: config.rateLimiters.markAsRead.windowMs,
  logLabel: 'setChannelNotificationSetting'
})
  .input(
    z.object({
      channelId: z.number().int().positive(),
      level: z.enum(['all', 'mentions', 'none']),
      muteForMinutes: z.number().int().min(1).max(MAX_MUTE_MINUTES).optional()
    })
  )
  .mutation(async ({ ctx, input }) => {
    await assertChannelAccess(ctx, input.channelId);

    const where = and(
      eq(channelNotificationSettings.channelId, input.channelId),
      eq(channelNotificationSettings.userId, ctx.userId)
    );

    invariant(input.muteForMinutes === undefined || input.level === 'none', {
      code: 'BAD_REQUEST',
      message: 'Only a mute can last for a while.'
    });

    // the default is the absence of a row, so going back to it leaves nothing behind
    if (input.level === 'mentions') {
      await db.delete(channelNotificationSettings).where(where);
      return;
    }

    const mutedUntil =
      input.muteForMinutes === undefined
        ? null
        : Date.now() + input.muteForMinutes * 60 * 1000;

    await db
      .insert(channelNotificationSettings)
      .values({
        userId: ctx.userId,
        channelId: input.channelId,
        level: input.level,
        mutedUntil,
        updatedAt: Date.now()
      })
      .onConflictDoUpdate({
        target: [
          channelNotificationSettings.channelId,
          channelNotificationSettings.userId
        ],
        set: { level: input.level, mutedUntil, updatedAt: Date.now() }
      });
  });

export { setChannelSettingRoute };
