import { ActivityLogType, OWNER_ROLE_ID, Permission } from '@sharkord/shared';
import { z } from 'zod';
import { db } from '../../db';
import { giveRoleToAllMembers } from '../../db/mutations/roles';
import { updateSettings } from '../../db/mutations/server';
import {
  publishMessage,
  publishSettings,
  publishUser
} from '../../db/publishers';
import { isDirectMessageChannel } from '../../db/queries/dms';
import { getReaction } from '../../db/queries/messages';
import { getRole } from '../../db/queries/roles';
import { messageReactions } from '../../db/schema';
import { loadMessageForWrite } from '../../helpers/load-message-for-write';
import { resolveKnownEmojiFileId } from '../../helpers/resolve-known-emoji-file-id';
import { enqueueActivityLog } from '../../queues/activity-log';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

// the reaction put on the rules message, so a new member has one to tap
const ACCEPT_EMOJI = 'white_check_mark';

// the new member lounge: reacting to the rules message gives a role, and the server's public
// channels are opened to that role rather than to everyone. both set, or both cleared
const setOnboardingRoute = protectedProcedure
  .input(
    z
      .object({
        messageId: z.number().int().positive().nullable(),
        roleId: z.number().int().positive().nullable(),
        // without it, closing the channels to everyone else locks out the members already here
        giveExistingMembers: z.boolean().default(false)
      })
      .refine(
        ({ messageId, roleId }) => (messageId === null) === (roleId === null),
        { message: 'Pick both the rules message and the role it gives.' }
      )
  )
  .mutation(async ({ ctx, input }) => {
    await ctx.needsPermission(Permission.MANAGE_SETTINGS);

    if (input.messageId === null || input.roleId === null) {
      await updateSettings({
        onboardingMessageId: null,
        onboardingRoleId: null
      });
      publishSettings();

      enqueueActivityLog({
        type: ActivityLogType.EDIT_SERVER_SETTINGS,
        userId: ctx.userId,
        details: {
          values: { onboardingMessageId: null, onboardingRoleId: null }
        }
      });

      return;
    }

    const [message, role] = await Promise.all([
      loadMessageForWrite(ctx, input.messageId),
      getRole(input.roleId)
    ]);

    invariant(role, {
      code: 'NOT_FOUND',
      message: 'Role not found'
    });

    invariant(!(await isDirectMessageChannel(message.channelId)), {
      code: 'BAD_REQUEST',
      message: 'The rules have to be in a server channel.'
    });

    invariant(role.id !== OWNER_ROLE_ID && !role.isDefault, {
      code: 'BAD_REQUEST',
      message: 'Pick a role new members do not already have.'
    });

    invariant(await ctx.hasPermission(role.permissions), {
      code: 'FORBIDDEN',
      message: 'You cannot assign a role with permissions that you do not have.'
    });

    await updateSettings({
      onboardingMessageId: message.id,
      onboardingRoleId: role.id
    });

    const existingReaction = await getReaction(
      message.id,
      ACCEPT_EMOJI,
      ctx.userId
    );

    if (!existingReaction) {
      await db.insert(messageReactions).values({
        messageId: message.id,
        emoji: ACCEPT_EMOJI,
        userId: ctx.userId,
        fileId: await resolveKnownEmojiFileId(ACCEPT_EMOJI),
        createdAt: Date.now()
      });

      publishMessage(message.id, message.channelId, 'update');
    }

    if (input.giveExistingMembers) {
      const recipients = giveRoleToAllMembers(role.id);

      for (const userId of recipients) {
        publishUser(userId, 'update');
      }
    }

    publishSettings();

    enqueueActivityLog({
      type: ActivityLogType.EDIT_SERVER_SETTINGS,
      userId: ctx.userId,
      details: {
        values: { onboardingMessageId: message.id, onboardingRoleId: role.id }
      }
    });
  });

export { setOnboardingRoute };
