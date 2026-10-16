import { Permission, WEBHOOK_NAME_MAX_LENGTH } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { isDirectMessageChannel } from '../../db/queries/dms';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { createWebhook } from '../../helpers/webhooks';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// the token is only ever returned here, the server keeps a hash of it
const addWebhookRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.adminCreate.maxRequests,
  windowMs: config.rateLimiters.adminCreate.windowMs,
  logLabel: 'addWebhook'
})
  .input(
    z.object({
      channelId: z.number().int().positive(),
      name: z.string().trim().min(1).max(WEBHOOK_NAME_MAX_LENGTH)
    })
  )
  .mutation(async ({ ctx, input }) => {
    await ctx.needsPermission(Permission.MANAGE_CHANNELS);
    await assertChannelAccess(ctx, input.channelId);

    invariant(!(await isDirectMessageChannel(input.channelId)), {
      code: 'BAD_REQUEST',
      message: 'Direct messages cannot have webhooks.'
    });

    const { webhook, token } = await createWebhook(
      input.channelId,
      input.name,
      ctx.userId
    );

    return { id: webhook.id, token };
  });

export { addWebhookRoute };
