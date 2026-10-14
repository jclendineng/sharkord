import {
  GROUP_DM_MAX_MEMBERS,
  GROUP_DM_NAME_MAX_LENGTH,
  ServerEvents
} from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { createGroupDirectMessage } from '../../db/mutations/dms';
import { publishChannelPermissions } from '../../db/publishers';
import { getFriendIds } from '../../db/queries/friends';
import { getSettings } from '../../db/queries/server';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// discord's new group: the caller and up to nine friends in one conversation
const createGroupRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.openDirectMessage.maxRequests,
  windowMs: config.rateLimiters.openDirectMessage.windowMs,
  logLabel: 'createGroupDirectMessage'
})
  .input(
    z.object({
      userIds: z
        .array(z.number().int().positive())
        .min(2)
        .max(GROUP_DM_MAX_MEMBERS - 1),
      name: z.string().trim().min(1).max(GROUP_DM_NAME_MAX_LENGTH).optional()
    })
  )
  .mutation(async ({ ctx, input }) => {
    const settings = await getSettings();

    invariant(settings.directMessagesEnabled, {
      code: 'FORBIDDEN',
      message: 'Direct messages are disabled on this server'
    });

    const others = [...new Set(input.userIds)].filter(
      (id) => id !== ctx.userId
    );

    invariant(others.length >= 2, {
      code: 'BAD_REQUEST',
      message: 'A group needs at least two other people.'
    });

    const friendIds = await getFriendIds(ctx.userId);

    invariant(
      others.every((id) => friendIds.has(id)),
      {
        code: 'FORBIDDEN',
        message: 'You can only add your friends to a group.'
      }
    );

    const memberIds = [ctx.userId, ...others];
    const channel = createGroupDirectMessage(
      ctx.userId,
      memberIds,
      input.name ?? null
    );

    ctx.pubsub.publishFor(memberIds, ServerEvents.CHANNEL_CREATE, channel);
    ctx.pubsub.publishFor(memberIds, ServerEvents.DM_CONVERSATION_OPEN, {
      channelId: channel.id
    });

    await publishChannelPermissions(memberIds);

    return { channelId: channel.id };
  });

export { createGroupRoute };
