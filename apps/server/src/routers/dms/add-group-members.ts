import { GROUP_DM_MAX_MEMBERS, ServerEvents } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { addGroupDirectMessageMembers } from '../../db/mutations/dms';
import { publishChannelPermissions } from '../../db/publishers';
import { getDirectMessageChannelParticipantIds } from '../../db/queries/dms';
import { getFriendIds } from '../../db/queries/friends';
import { channels, groupDms } from '../../db/schema';
import { assertChannelAccess } from '../../helpers/assert-channel-access';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// anyone in a group can bring their friends in, up to ten people in all
const addGroupMembersRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.openDirectMessage.maxRequests,
  windowMs: config.rateLimiters.openDirectMessage.windowMs,
  logLabel: 'addGroupDirectMessageMembers'
})
  .input(
    z.object({
      channelId: z.number().int().positive(),
      userIds: z
        .array(z.number().int().positive())
        .min(1)
        .max(GROUP_DM_MAX_MEMBERS - 1)
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

    const memberIds = await getDirectMessageChannelParticipantIds(
      input.channelId
    );
    const newIds = [...new Set(input.userIds)].filter(
      (id) => !memberIds.includes(id)
    );

    invariant(newIds.length > 0, {
      code: 'BAD_REQUEST',
      message: 'They are already in the group.'
    });

    invariant(memberIds.length + newIds.length <= GROUP_DM_MAX_MEMBERS, {
      code: 'BAD_REQUEST',
      message: `A group can have at most ${GROUP_DM_MAX_MEMBERS} people.`
    });

    const friendIds = await getFriendIds(ctx.userId);

    invariant(
      newIds.every((id) => friendIds.has(id)),
      {
        code: 'FORBIDDEN',
        message: 'You can only add your friends to a group.'
      }
    );

    await addGroupDirectMessageMembers(input.channelId, newIds);

    const channel = await db
      .select()
      .from(channels)
      .where(eq(channels.id, input.channelId))
      .limit(1)
      .get();

    const everyone = [...memberIds, ...newIds];

    if (channel) {
      ctx.pubsub.publishFor(newIds, ServerEvents.CHANNEL_CREATE, channel);
    }

    ctx.pubsub.publishFor(everyone, ServerEvents.DM_CONVERSATION_OPEN, {
      channelId: input.channelId
    });

    await publishChannelPermissions(newIds);
  });

export { addGroupMembersRoute };
