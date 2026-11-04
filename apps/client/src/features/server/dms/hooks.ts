import type { IRootState } from '@/features/store';
import { useSelector } from 'react-redux';
import {
  directMessagesSelector,
  friendListsSelector,
  friendStatusSelector,
  isUserBlockedSelector
} from './selectors';

export const useDirectMessages = () => useSelector(directMessagesSelector);

export const useFriendLists = () => useSelector(friendListsSelector);

export const useFriendStatus = (userId: number) =>
  useSelector((state: IRootState) => friendStatusSelector(state, userId));

export const useIsUserBlocked = (userId: number) =>
  useSelector((state: IRootState) => isUserBlockedSelector(state, userId));
