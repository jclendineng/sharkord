import { z } from 'zod';
import { config } from '../../config';
import { closeDirectMessage } from '../../db/mutations/dms';
import { isDirectMessageChannel } from '../../db/queries/dms';
import { getSettings } from '../../db/queries/server';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// discord's close dm: the conversation leaves the caller's list until a new message in it, the
// other participant's list and the messages themselves are untouched
const closeDirectMessageRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.openDirectMessage.maxRequests,
  windowMs: config.rateLimiters.openDirectMessage.windowMs,
  logLabel: 'closeDirectMessage'
})
  .input(z.object({ channelId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    const settings = await getSettings();

    invariant(settings.directMessagesEnabled, {
      code: 'FORBIDDEN',
      message: 'Direct messages are disabled on this server'
    });

    const isDm = await isDirectMessageChannel(input.channelId);

    invariant(isDm, {
      code: 'NOT_FOUND',
      message: 'Conversation not found'
    });

    await assertChannelAccess(ctx, input.channelId);

    await closeDirectMessage(input.channelId, ctx.userId);
  });

export { closeDirectMessageRoute };
