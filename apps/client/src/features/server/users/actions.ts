import { store } from '@/features/store';
import { UserStatus, type TJoinedPublicUser } from '@sharkord/shared';
import { serverSliceActions } from '../slice';
import { userByIdSelector } from './selectors';

export const addUser = (user: TJoinedPublicUser) => {
  store.dispatch(serverSliceActions.addUser(user));
};

export const updateUser = (
  userId: number,
  user: Partial<TJoinedPublicUser>
) => {
  store.dispatch(serverSliceActions.updateUser({ userId, user }));
};

export const wipeUser = (userId: number) => {
  store.dispatch(serverSliceActions.wipeUser({ userId }));
};

export const reassignUser = (userId: number, targetUser: number) => {
  store.dispatch(
    serverSliceActions.reassignUser({ userId, deletedUserId: targetUser })
  );
};

// joins, creates and updates arrive on separate subscriptions, so under load one can overtake
// another: a join snapshot taken before a rename can land after it. a known user's profile is
// therefore only ever changed by an update, and a join only brings the status
export const handleUserJoin = (user: TJoinedPublicUser) => {
  const state = store.getState();
  const foundUser = userByIdSelector(state, user.id);

  if (foundUser) {
    // the server sends the status the user picked, do not disturb included
    updateUser(user.id, { status: user.status ?? UserStatus.ONLINE });
  } else {
    addUser(user);
  }
};

// an update that overtook the create or join introducing the user is the newest copy there
// is, so it adds the user instead of being dropped. the late create is then ignored
export const handleUserUpdate = (user: TJoinedPublicUser) => {
  const state = store.getState();
  const foundUser = userByIdSelector(state, user.id);

  if (foundUser) {
    updateUser(user.id, user);
  } else {
    addUser(user);
  }
};
