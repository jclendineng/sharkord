import { logDebug } from '@/helpers/browser-logger';
import { getTRPCClient } from '@/lib/trpc';
import { handleSubscriptionError } from '../subscription-error';
import { loadDirectMessages, loadFriends } from './actions';

// conversations opened, groups changed and friendships, each fetched again as a whole: the
// events only say what changed, not what it looks like now
const subscribeToDirectMessages = () => {
  const trpc = getTRPCClient();

  loadDirectMessages();
  loadFriends();

  const onConversationOpenSub = trpc.dms.onConversationOpen.subscribe(
    undefined,
    {
      onData: (event) => {
        logDebug('[EVENTS] dms.onConversationOpen', { event });
        loadDirectMessages();
      },
      onError: handleSubscriptionError('onConversationOpen')
    }
  );

  const onFriendshipUpdateSub = trpc.friends.onUpdate.subscribe(undefined, {
    onData: (event) => {
      logDebug('[EVENTS] friends.onUpdate', { event });
      loadFriends();
    },
    onError: handleSubscriptionError('onFriendshipUpdate')
  });

  return () => {
    onConversationOpenSub.unsubscribe();
    onFriendshipUpdateSub.unsubscribe();
  };
};

export { subscribeToDirectMessages };
