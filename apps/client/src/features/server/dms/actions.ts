import { store } from '@/features/store';
import { i18n } from '@/i18n';
import { getTRPCClient } from '@/lib/trpc';
import { getTrpcError } from '@sharkord/shared';
import { toast } from 'sonner';
import { serverSliceActions } from '../slice';

// the conversation list as the server has it. a server with direct messages off refuses, the
// list then stays empty
export const loadDirectMessages = async () => {
  try {
    const trpc = getTRPCClient();
    const conversations = await trpc.dms.get.query();

    store.dispatch(serverSliceActions.setDirectMessages(conversations));
  } catch {
    store.dispatch(serverSliceActions.setDirectMessages([]));
  }
};

// a server from before friends has none
export const loadFriends = async () => {
  try {
    const trpc = getTRPCClient();
    const lists = await trpc.friends.get.query();

    store.dispatch(serverSliceActions.setFriendLists(lists));
  } catch {
    // keeps what it had
  }
};

export type TFriendshipAction = 'request' | 'accept' | 'remove';

// the user popover and the friends dialog both send these, and both want the lists fresh after
export const changeFriendship = async (
  action: TFriendshipAction,
  userId: number
) => {
  try {
    const trpc = getTRPCClient();

    if (action === 'request') {
      await trpc.friends.request.mutate({ userId });
    } else if (action === 'accept') {
      await trpc.friends.accept.mutate({ userId });
    } else {
      await trpc.friends.remove.mutate({ userId });
    }

    await loadFriends();

    return true;
  } catch (error) {
    toast.error(getTrpcError(error, i18n.t('sidebar:failedChangeFriendship')));

    return false;
  }
};
