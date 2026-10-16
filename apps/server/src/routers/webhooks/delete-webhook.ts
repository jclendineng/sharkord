import { Permission } from '@sharkord/shared';
import { z } from 'zod';
import { getWebhookById } from '../../db/queries/webhooks';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { deleteWebhook } from '../../helpers/webhooks';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

const deleteWebhookRoute = protectedProcedure
  .input(z.object({ webhookId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    await ctx.needsPermission(Permission.MANAGE_CHANNELS);

    const webhook = await getWebhookById(input.webhookId);

    invariant(webhook, {
      code: 'NOT_FOUND',
      message: 'Webhook not found.'
    });

    await assertChannelAccess(ctx, webhook.channelId);
    await deleteWebhook(webhook.id);
  });

export { deleteWebhookRoute };
