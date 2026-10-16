import { useDevices } from '@/components/devices-provider/hooks/use-devices';
import type { TRemoteStreams } from '@/types';
import { StreamKind } from '@sharkord/shared';
import { memo, useEffect, useRef } from 'react';
import { useVolumeControl } from './volume-control-context';

type TStreamAudioMuterProps = {
  remoteUserStreams: TRemoteStreams;
};

// with mute stream audio on, each screen share's sound starts muted. a stream is only muted once,
// when it first arrives, so unmuting it from its volume control sticks
export const StreamAudioMuter = memo(
  ({ remoteUserStreams }: TStreamAudioMuterProps) => {
    const { devices } = useDevices();
    const { getVolume, toggleMute, getUserScreenVolumeKey } =
      useVolumeControl();
    const handledStreams = useRef(new WeakSet<MediaStream>());

    useEffect(() => {
      if (!devices.muteStreamAudio) return;

      Object.entries(remoteUserStreams).forEach(([userId, streams]) => {
        const stream = streams?.[StreamKind.SCREEN_AUDIO];

        if (!stream || handledStreams.current.has(stream)) return;

        handledStreams.current.add(stream);

        const key = getUserScreenVolumeKey(Number(userId));

        if (getVolume(key) > 0) {
          toggleMute(key);
        }
      });
    }, [
      devices.muteStreamAudio,
      remoteUserStreams,
      getVolume,
      toggleMute,
      getUserScreenVolumeKey
    ]);

    return null;
  }
);

StreamAudioMuter.displayName = 'StreamAudioMuter';
