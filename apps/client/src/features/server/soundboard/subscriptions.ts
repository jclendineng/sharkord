import { logDebug } from '@/helpers/browser-logger';
import { getTRPCClient } from '@/lib/trpc';
import type { TJoinedSoundboardSound } from '@sharkord/shared';
import { handleSubscriptionError } from '../subscription-error';
import { removeSound, upsertSound } from './actions';

const subscribeToSoundboard = () => {
  const trpc = getTRPCClient();

  const onCreateSub = trpc.soundboard.onCreate.subscribe(undefined, {
    onData: (sound: TJoinedSoundboardSound) => {
      logDebug('[EVENTS] soundboard.onCreate', { sound });
      upsertSound(sound);
    },
    onError: handleSubscriptionError('onSoundCreate')
  });

  const onUpdateSub = trpc.soundboard.onUpdate.subscribe(undefined, {
    onData: (sound: TJoinedSoundboardSound) => {
      logDebug('[EVENTS] soundboard.onUpdate', { sound });
      upsertSound(sound);
    },
    onError: handleSubscriptionError('onSoundUpdate')
  });

  const onDeleteSub = trpc.soundboard.onDelete.subscribe(undefined, {
    onData: (soundId: number) => {
      logDebug('[EVENTS] soundboard.onDelete', { soundId });
      removeSound(soundId);
    },
    onError: handleSubscriptionError('onSoundDelete')
  });

  return () => {
    onCreateSub.unsubscribe();
    onUpdateSub.unsubscribe();
    onDeleteSub.unsubscribe();
  };
};

export { subscribeToSoundboard };
