import { pushVoiceDebugEvent } from '@/helpers/voice-debug';
import { store } from '../store';
import { connectedSelector } from './selectors';
import { serverSliceActions } from './slice';

export const handleSubscriptionError =
  (subscriptionName: string) => (error: unknown) => {
    console.error(`${subscriptionName} subscription error:`, error);

    pushVoiceDebugEvent('error', `${subscriptionName} subscription error`, {
      error: String(error)
    });

    if (connectedSelector(store.getState())) {
      store.dispatch(serverSliceActions.setDisconnectInfo(undefined));
    }
  };
