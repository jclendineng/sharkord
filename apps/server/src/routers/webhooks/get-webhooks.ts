import { Permission } from '@sharkord/shared';
import { z } from 'zod';
import { getWebhooksForChannel } from '../../db/queries/webhooks';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { protectedProcedure } from '../../utils/trpc';

const getWebhooksRoute = protectedProcedure
  .input(z.object({ channelId: z.number().int().positive() }))
  .query(async ({ ctx, input }) => {
    await ctx.needsPermission(Permission.MANAGE_CHANNELS);
    await assertChannelAccess(ctx, input.channelId);

    return getWebhooksForChannel(input.channelId);
  });

export { getWebhooksRoute };
