import {
  CHANNEL_RETENTION_MAX_DAYS,
  CHANNEL_RETENTION_MIN_DAYS,
  Permission
} from '@sharkord/shared';
import { z } from 'zod';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { countExpiredMessages } from '../../helpers/message-retention';
import { protectedProcedure } from '../../utils/trpc';

// the dry run: how many messages a retention period would delete if it ran now
const getRetentionPreviewRoute = protectedProcedure
  .input(
    z.object({
      channelId: z.number().int().positive(),
      retentionDays: z
        .number()
        .int()
        .min(CHANNEL_RETENTION_MIN_DAYS)
        .max(CHANNEL_RETENTION_MAX_DAYS)
    })
  )
  .query(async ({ ctx, input }) => {
    await ctx.needsPermission(Permission.MANAGE_CHANNELS);
    await assertChannelAccess(ctx, input.channelId);

    return countExpiredMessages(input.channelId, input.retentionDays);
  });

export { getRetentionPreviewRoute };
