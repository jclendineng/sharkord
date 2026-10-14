import { ServerEvents } from '@sharkord/shared';
import { protectedProcedure } from '../../utils/trpc';

// someone the caller asked, was asked by or is friends with changed it, the list is fetched again
const onFriendshipUpdateRoute = protectedProcedure.subscription(
  async ({ ctx }) => {
    return ctx.pubsub.subscribeFor(ctx.userId, ServerEvents.FRIENDSHIP_UPDATE);
  }
);

export { onFriendshipUpdateRoute };
