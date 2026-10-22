import { Permission } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { isDirectMessageChannel } from '../../db/queries/dms';
import { loadMessageForWrite } from '../../helpers/load-message-for-write';
import { setMessagePinned } from '../../helpers/message-pin';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const toggleMessagePinRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.messageAction.maxRequests,
  windowMs: config.rateLimiters.messageAction.windowMs,
  logLabel: 'toggleMessagePin'
})
  .input(z.object({ messageId: z.number() }))
  .mutation(async ({ ctx, input }) => {
    // which permission applies depends on the message's channel, so it is loaded first. the
    // load proves the caller can see the channel, so the check leaks nothing it should not
    const message = await loadMessageForWrite(ctx, input.messageId);
    const isDm = await isDirectMessageChannel(message.channelId);

    await ctx.needsPermission(
      isDm ? Permission.PIN_DM_MESSAGES : Permission.PIN_MESSAGES
    );

    await setMessagePinned(message, !message.pinned, ctx.user.id);
  });

export { toggleMessagePinRoute };
