import { ServerEvents } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { leaveGroupDirectMessage } from '../../db/mutations/dms';
import { publishChannelPermissions } from '../../db/publishers';
import { groupDms } from '../../db/schema';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// out of a group, which is gone for good once nobody is left in it
const leaveGroupRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.openDirectMessage.maxRequests,
  windowMs: config.rateLimiters.openDirectMessage.windowMs,
  logLabel: 'leaveGroupDirectMessage'
})
  .input(z.object({ channelId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    const group = await db
      .select({ channelId: groupDms.channelId })
      .from(groupDms)
      .where(eq(groupDms.channelId, input.channelId))
      .limit(1)
      .get();

    invariant(group, { code: 'NOT_FOUND', message: 'Group not found' });

    await assertChannelAccess(ctx, input.channelId);

    const remaining = leaveGroupDirectMessage(input.channelId, ctx.userId);

    ctx.pubsub.publishFor(
      ctx.userId,
      ServerEvents.CHANNEL_DELETE,
      input.channelId
    );

    if (remaining.length > 0) {
      ctx.pubsub.publishFor(remaining, ServerEvents.DM_CONVERSATION_OPEN, {
        channelId: input.channelId
      });
    }

    await publishChannelPermissions([ctx.userId]);
  });

export { leaveGroupRoute };
