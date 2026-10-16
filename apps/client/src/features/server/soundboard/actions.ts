import { store } from '@/features/store';
import { getFileUrl } from '@/helpers/get-file-url';
import { playSoundFile } from '@/helpers/soundboard-audio';
import type { TJoinedSoundboardSound } from '@sharkord/shared';
import { currentVoiceChannelIdSelector } from '../channels/selectors';
import { serverSliceActions } from '../slice';
import { ownVoiceStateSelector } from '../voice/selectors';
import { soundByIdSelector } from './selectors';

export const upsertSound = (sound: TJoinedSoundboardSound) => {
  store.dispatch(serverSliceActions.upsertSound(sound));
};

export const removeSound = (soundId: number) => {
  store.dispatch(serverSliceActions.removeSound({ soundId }));
};

// a sound played in the call this app is in. every app plays it itself, so a deafened member
// does not hear it and nobody's mic picks it up
export const playSoundboardSound = (channelId: number, soundId: number) => {
  const state = store.getState();
  const currentVoiceChannelId = currentVoiceChannelIdSelector(state);

  if (currentVoiceChannelId !== channelId) return;

  const ownVoiceState = ownVoiceStateSelector(state);

  if (ownVoiceState.soundMuted) return;

  const sound = soundByIdSelector(state, soundId);

  if (!sound) return;

  playSoundFile(getFileUrl(sound.file), sound.volume);
};
