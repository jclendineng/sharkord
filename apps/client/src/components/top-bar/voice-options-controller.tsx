import {
  setAlwaysShowVoiceControls,
  setHideNonVideoParticipants,
  setHideOwnScreenShare,
  setIncomingVideoOff,
  setShowUserBannersInVoice
} from '@/features/server/voice/actions';
import {
  useAlwaysShowVoiceControls,
  useHideNonVideoParticipants,
  useHideOwnScreenShare,
  useIncomingVideoOff,
  useShowUserBannersInVoice
} from '@/features/server/voice/hooks';
import {
  Button,
  Popover,
  PopoverContent,
  PopoverTrigger,
  Switch,
  Tooltip
} from '@sharkord/ui';
import { Settings } from 'lucide-react';
import { memo, useCallback } from 'react';
import { useTranslation } from 'react-i18next';

const VoiceOptionsController = memo(() => {
  const { t } = useTranslation('topbar');
  const hideNonVideoParticipants = useHideNonVideoParticipants();
  const showUserBanners = useShowUserBannersInVoice();
  const hideOwnScreenShare = useHideOwnScreenShare();
  const alwaysShowVoiceControls = useAlwaysShowVoiceControls();
  const incomingVideoOff = useIncomingVideoOff();

  const handleToggleHideNonVideo = useCallback((checked: boolean) => {
    setHideNonVideoParticipants(checked);
  }, []);

  const handleToggleIncomingVideoOff = useCallback((checked: boolean) => {
    setIncomingVideoOff(checked);
  }, []);

  const handleToggleShowUserBanners = useCallback((checked: boolean) => {
    setShowUserBannersInVoice(checked);
  }, []);

  const handleToggleHideOwnScreenShare = useCallback((checked: boolean) => {
    setHideOwnScreenShare(checked);
  }, []);

  const handleToggleAlwaysShowVoiceControls = useCallback(
    (checked: boolean) => {
      setAlwaysShowVoiceControls(checked);
    },
    []
  );

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="sm" className="h-6 px-2">
          <Tooltip content={t('voiceOptions')} asChild={false}>
            <Settings className="w-4 h-4" />
          </Tooltip>
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-80">
        <div className="space-y-3">
          <h4 className="font-medium text-sm cursor-default mb-3">
            {t('voiceOptions')}
          </h4>

          <div className="flex items-center justify-between space-x-3">
            <label
              htmlFor="hide-non-video"
              className="text-sm text-foreground cursor-pointer select-none flex-1"
            >
              {t('hideNonVideoParticipants')}
            </label>
            <Switch
              id="hide-non-video"
              checked={hideNonVideoParticipants}
              onCheckedChange={handleToggleHideNonVideo}
            />
          </div>

          <div className="flex items-center justify-between space-x-3">
            <label
              htmlFor="incoming-video-off"
              className="text-sm text-foreground cursor-pointer select-none flex-1"
            >
              {t('incomingVideoOff')}
            </label>
            <Switch
              id="incoming-video-off"
              checked={incomingVideoOff}
              onCheckedChange={handleToggleIncomingVideoOff}
            />
          </div>

          <div className="flex items-center justify-between space-x-3">
            <label
              htmlFor="show-user-banners"
              className="text-sm text-foreground cursor-pointer select-none flex-1"
            >
              {t('displayUserBanners')}
            </label>
            <Switch
              id="show-user-banners"
              checked={showUserBanners}
              onCheckedChange={handleToggleShowUserBanners}
            />
          </div>

          <div className="flex items-center justify-between space-x-3">
            <label
              htmlFor="always-show-voice-controls"
              className="text-sm text-foreground cursor-pointer select-none flex-1"
            >
              {t('alwaysShowVoiceControls')}
            </label>
            <Switch
              id="always-show-voice-controls"
              checked={alwaysShowVoiceControls}
              onCheckedChange={handleToggleAlwaysShowVoiceControls}
            />
          </div>

          <div className="flex items-center justify-between space-x-3">
            <label
              htmlFor="hide-own-screen-share"
              className="text-sm text-foreground cursor-pointer select-none flex-1"
            >
              {t('hideOwnScreenShare')}
            </label>
            <Switch
              id="hide-own-screen-share"
              checked={hideOwnScreenShare}
              onCheckedChange={handleToggleHideOwnScreenShare}
            />
          </div>
        </div>
      </PopoverContent>
    </Popover>
  );
});

VoiceOptionsController.displayName = 'VoiceOptionsController';

export { VoiceOptionsController };
