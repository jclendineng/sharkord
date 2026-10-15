import type { IRootState } from '@/features/store';
import { useSelector } from 'react-redux';
import {
  directMessagesSelector,
  friendListsSelector,
  friendStatusSelector
} from './selectors';

export const useDirectMessages = () => useSelector(directMessagesSelector);

export const useFriendLists = () => useSelector(friendListsSelector);

export const useFriendStatus = (userId: number) =>
  useSelector((state: IRootState) => friendStatusSelector(state, userId));
