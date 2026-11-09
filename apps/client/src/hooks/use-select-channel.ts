import { setSelectedChannelId } from '@/features/server/channels/actions';
import { useCurrentVoiceChannelId } from '@/features/server/channels/hooks';
import {
  channelByIdSelector,
  currentVoiceChannelIdSelector
} from '@/features/server/channels/selectors';
import { joinVoice, leaveVoice } from '@/features/server/voice/actions';
import { useVoice } from '@/features/server/voice/hooks';
import { isVoiceJoiningSelector } from '@/features/server/voice/selectors';
import { store } from '@/features/store';
import { LocalStorageKey, setLocalStorageItem } from '@/helpers/storage';
import { ChannelType } from '@sharkord/shared';
import { useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

// the single entry point for navigating to a channel, it also joins voice and
// remembers the last text channel, so never dispatch setSelectedChannelId directly
const useSelectChannel = () => {
  const { t } = useTranslation('common');

  const { init } = useVoice();
  const currentVoiceChannelId = useCurrentVoiceChannelId();

  return useCallback(
    async (channelId: number, options?: { keepsView?: boolean }) => {
      const channel = channelByIdSelector(store.getState(), channelId);

      if (!channel) return;

      const state = store.getState();

      // a join under way takes no second one, and the view stays with the call it is joining
      if (
        channel.type === ChannelType.VOICE &&
        channel.id !== currentVoiceChannelIdSelector(state) &&
        isVoiceJoiningSelector(state)
      ) {
        return;
      }

      if (!options?.keepsView) {
        setSelectedChannelId(channel.id);
      }

      if (channel.type !== ChannelType.VOICE) {
        // persist selected channel for non-voice channels
        setLocalStorageItem(
          LocalStorageKey.LAST_SELECTED_CHANNEL,
          channel.id.toString()
        );
      }

      if (
        channel.type === ChannelType.VOICE &&
        currentVoiceChannelId !== channel.id
      ) {
        const response = await joinVoice(channel.id);

        if (!response) return;

        try {
          await init(response, channel.id);
        } catch {
          await leaveVoice({ reason: 'init_failed' });

          toast.error(t('common:failedInitVoiceConnection'));
        }
      }
    },
    [currentVoiceChannelId, init, t]
  );
};

export { useSelectChannel };
