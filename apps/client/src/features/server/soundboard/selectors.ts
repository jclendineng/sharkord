import type { IRootState } from '@/features/store';
import { createCachedSelector } from 're-reselect';

export const soundsSelector = (state: IRootState) => state.server.sounds;

export const soundByIdSelector = createCachedSelector(
  [soundsSelector, (_: IRootState, soundId: number) => soundId],
  (sounds, soundId) => sounds.find((sound) => sound.id === soundId)
)((_, soundId) => soundId);
