import { ServerEvents } from '@sharkord/shared';
import { protectedProcedure, t } from '../../utils/trpc';
import { addGroupMembersRoute } from './add-group-members';
import { closeDirectMessageRoute } from './close-direct-message';
import { createGroupRoute } from './create-group';
import { getDirectMessagesRoute } from './get-direct-messages';
import { leaveGroupRoute } from './leave-group';
import { openDirectMessageRoute } from './open-direct-message';
import { renameGroupRoute } from './rename-group';

const onDmConversationOpenRoute = protectedProcedure.subscription(
  async ({ ctx }) => {
    return ctx.pubsub.subscribeFor(
      ctx.userId,
      ServerEvents.DM_CONVERSATION_OPEN
    );
  }
);

export const dmsRouter = t.router({
  get: getDirectMessagesRoute,
  open: openDirectMessageRoute,
  close: closeDirectMessageRoute,
  createGroup: createGroupRoute,
  addGroupMembers: addGroupMembersRoute,
  leaveGroup: leaveGroupRoute,
  renameGroup: renameGroupRoute,
  onConversationOpen: onDmConversationOpenRoute
});
