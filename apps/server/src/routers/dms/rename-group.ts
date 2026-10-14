import { GROUP_DM_NAME_MAX_LENGTH, ServerEvents } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { renameGroupDirectMessage } from '../../db/mutations/dms';
import { getDirectMessageChannelParticipantIds } from '../../db/queries/dms';
import { groupDms } from '../../db/schema';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// anyone in the group names it, null goes back to listing the people in it
const renameGroupRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.openDirectMessage.maxRequests,
  windowMs: config.rateLimiters.openDirectMessage.windowMs,
  logLabel: 'renameGroupDirectMessage'
})
  .input(
    z.object({
      channelId: z.number().int().positive(),
      name: z.string().trim().min(1).max(GROUP_DM_NAME_MAX_LENGTH).nullable()
    })
  )
  .mutation(async ({ ctx, input }) => {
    const group = await db
      .select({ channelId: groupDms.channelId })
      .from(groupDms)
      .where(eq(groupDms.channelId, input.channelId))
      .limit(1)
      .get();

    invariant(group, { code: 'NOT_FOUND', message: 'Group not found' });

    await assertChannelAccess(ctx, input.channelId);

    await renameGroupDirectMessage(input.channelId, input.name);

    const memberIds = await getDirectMessageChannelParticipantIds(
      input.channelId
    );

    ctx.pubsub.publishFor(memberIds, ServerEvents.DM_CONVERSATION_OPEN, {
      channelId: input.channelId
    });
  });

export { renameGroupRoute };
