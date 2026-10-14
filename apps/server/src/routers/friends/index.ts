import { t } from '../../utils/trpc';
import { acceptFriendRoute } from './accept-friend';
import { onFriendshipUpdateRoute } from './events';
import { getFriendsRoute } from './get-friends';
import { removeFriendRoute } from './remove-friend';
import { requestFriendRoute } from './request-friend';

export const friendsRouter = t.router({
  get: getFriendsRoute,
  request: requestFriendRoute,
  accept: acceptFriendRoute,
  remove: removeFriendRoute,
  onUpdate: onFriendshipUpdateRoute
});
