import { getFriendLists } from '../../db/queries/friends';
import { protectedProcedure } from '../../utils/trpc';

// the caller's friends and the requests waiting on either side, as user ids
const getFriendsRoute = protectedProcedure.query(async ({ ctx }) =>
  getFriendLists(ctx.userId)
);

export { getFriendsRoute };
