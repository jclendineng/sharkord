import type { IRootState } from '@/features/store';
import { createCachedSelector } from 're-reselect';

export type TFriendStatus = 'friend' | 'incoming' | 'outgoing' | 'none';

export const directMessagesSelector = (state: IRootState) =>
  state.server.directMessages;

export const friendListsSelector = (state: IRootState) =>
  state.server.friendLists;

export const friendStatusSelector = createCachedSelector(
  [friendListsSelector, (_: IRootState, userId: number) => userId],
  (lists, userId): TFriendStatus => {
    if (lists.friends.includes(userId)) {
      return 'friend';
    }

    if (lists.incoming.includes(userId)) {
      return 'incoming';
    }

    if (lists.outgoing.includes(userId)) {
      return 'outgoing';
    }

    return 'none';
  }
)((_, userId: number) => userId);
