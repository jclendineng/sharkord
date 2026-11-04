import { t } from '../../utils/trpc';
import { acceptFriendRoute } from './accept-friend';
import { blockUserRoute } from './block-user';
import { onFriendshipUpdateRoute } from './events';
import { getFriendsRoute } from './get-friends';
import { removeFriendRoute } from './remove-friend';
import { requestFriendRoute } from './request-friend';
import { unblockUserRoute } from './unblock-user';

export const friendsRouter = t.router({
  get: getFriendsRoute,
  request: requestFriendRoute,
  accept: acceptFriendRoute,
  remove: removeFriendRoute,
  block: blockUserRoute,
  unblock: unblockUserRoute,
  onUpdate: onFriendshipUpdateRoute
});
