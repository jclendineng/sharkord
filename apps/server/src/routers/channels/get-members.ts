import { ChannelPermission } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { getAffectedUserIdsForChannel } from '../../db/queries/channels';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// the ids of everyone who can see a channel, for the members tab of a search started in it
const getMembersRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.getMessages.maxRequests,
  windowMs: config.rateLimiters.getMessages.windowMs,
  logLabel: 'getChannelMembers'
})
  .input(
    z.object({
      channelId: z.number().int().positive()
    })
  )
  .query(async ({ ctx, input }) => {
    await assertChannelAccess(ctx, input.channelId);

    return getAffectedUserIdsForChannel(
      input.channelId,
      ChannelPermission.VIEW_CHANNEL
    );
  });

export { getMembersRoute };
