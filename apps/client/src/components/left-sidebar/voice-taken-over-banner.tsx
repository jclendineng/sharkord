import { useVoiceSession } from '@/features/server/voice/hooks';
import { useSelectChannel } from '@/hooks/use-select-channel';
import { Button } from '@sharkord/ui';
import { memo, useCallback } from 'react';
import { useTranslation } from 'react-i18next';

const VoiceTakenOverBanner = memo(() => {
  const { t } = useTranslation('sidebar');
  const voiceSession = useVoiceSession();
  const selectChannel = useSelectChannel();
  const channelId =
    voiceSession.phase === 'takenOver' ? voiceSession.channelId : undefined;

  const handleReconnect = useCallback(() => {
    if (channelId === undefined) return;

    selectChannel(channelId, { keepsView: true });
  }, [channelId, selectChannel]);

  if (channelId === undefined) return null;

  return (
    <div
      role="status"
      className="flex items-center gap-2 bg-red-600 px-3 py-2 text-xs font-semibold text-white"
    >
      <span className="min-w-0 flex-1">{t('voiceTakenOver')}</span>
      <Button
        variant="ghost"
        size="sm"
        className="h-7 shrink-0 border border-white/70 px-2 text-white hover:bg-white/10 hover:text-white"
        onClick={handleReconnect}
      >
        {t('voiceTakenOverReconnect')}
      </Button>
    </div>
  );
});

export { VoiceTakenOverBanner };
