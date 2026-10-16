import type { TDeviceSettings } from '@/types';
import { SOUND_MAX_VOLUME } from '@sharkord/shared';
import { applyAudioOutputDevice } from './audio-output';
import { getLocalStorageItemAsJSON, LocalStorageKey } from './storage';

// out of the speaker the call plays through, at the sound's own volume times this member's
// soundboard volume. read from storage rather than the devices context, since a sound arrives
// on a subscription outside react
const playSoundFile = async (url: string, soundVolume: number) => {
  const devices = getLocalStorageItemAsJSON<TDeviceSettings>(
    LocalStorageKey.DEVICES_SETTINGS
  );
  const soundboardVolume = devices?.soundboardVolume ?? SOUND_MAX_VOLUME;
  const audio = new Audio(url);

  audio.volume = Math.min(
    (soundVolume / SOUND_MAX_VOLUME) * (soundboardVolume / SOUND_MAX_VOLUME),
    1
  );

  await applyAudioOutputDevice(audio, devices?.playbackId, false);

  try {
    await audio.play();
  } catch {
    // a browser that has not been clicked yet refuses to play. joining the call was a click,
    // so this is only a tab that was never touched
  }
};

export { playSoundFile };
