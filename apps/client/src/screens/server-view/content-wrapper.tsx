import { TextChannel } from '@/components/channel-view/text';
import { VoiceChannel } from '@/components/channel-view/voice';
import { PluginSlotRenderer } from '@/components/plugin-slot-renderer';
import { setMobileDrawer } from '@/features/app/actions';
import {
  useSelectedChannelId,
  useSelectedChannelType
} from '@/features/server/channels/hooks';
import {
  useActiveFullscreenPluginId,
  useServerName
} from '@/features/server/hooks';
import { MobileDrawer } from '@/types';
import { ChannelType, PluginSlot } from '@sharkord/shared';
import { Alert, AlertDescription, Button } from '@sharkord/ui';
import { AlertTriangle, ArrowLeft, ArrowRight, Menu } from 'lucide-react';
import { memo, useCallback } from 'react';
import { useTranslation } from 'react-i18next';

// the public beta until the app is on the app store
const IOS_APP_URL = 'https://testflight.apple.com/join/svXFDNEK';

// an ipad's safari asks for the desktop site and says it is a mac, only its touch screen gives it away
const isIosDevice =
  /iPhone|iPad|iPod/.test(navigator.userAgent) ||
  (navigator.userAgent.includes('Macintosh') && navigator.maxTouchPoints > 1);

type TContentWrapperProps = {
  isDmMode: boolean;
  selectedDmChannelId?: number;
};

const ContentWrapper = memo(
  ({ isDmMode, selectedDmChannelId }: TContentWrapperProps) => {
    const { t } = useTranslation();
    const selectedChannelId = useSelectedChannelId();
    const selectedChannelType = useSelectedChannelType();
    const serverName = useServerName();
    const activeFullscreenPluginId = useActiveFullscreenPluginId();

    const onOpenChannelsClick = useCallback(() => {
      setMobileDrawer(MobileDrawer.CHANNELS);
    }, []);

    const onOpenMembersClick = useCallback(() => {
      setMobileDrawer(MobileDrawer.MEMBERS);
    }, []);

    if (activeFullscreenPluginId) {
      return (
        <main className="flex flex-1 flex-col bg-background relative min-w-0 min-h-0">
          <div className="flex-col gap-2 h-full w-full flex overflow-auto relative bg-background">
            <PluginSlotRenderer
              slotId={PluginSlot.FULL_SCREEN}
              onlyPluginId={activeFullscreenPluginId}
            />
          </div>
        </main>
      );
    }

    let content;

    if (isDmMode) {
      if (selectedDmChannelId) {
        content = (
          <TextChannel
            key={selectedDmChannelId}
            channelId={selectedDmChannelId}
          />
        );
      } else {
        content = (
          <div className="flex flex-col gap-4 h-full items-center justify-center text-sm text-muted-foreground">
            {t('selectDmPrompt')}
            <Button
              variant="outline"
              className="md:hidden"
              onClick={onOpenChannelsClick}
            >
              <Menu />
              {t('openChannelList')}
            </Button>
          </div>
        );
      }

      return (
        <main className="flex flex-1 flex-col bg-background relative min-w-0 min-h-0">
          {content}
        </main>
      );
    }

    if (selectedChannelId) {
      if (selectedChannelType === ChannelType.TEXT) {
        content = (
          <TextChannel key={selectedChannelId} channelId={selectedChannelId} />
        );
      } else if (selectedChannelType === ChannelType.VOICE) {
        content = (
          <VoiceChannel key={selectedChannelId} channelId={selectedChannelId} />
        );
      }
    } else {
      let mobileNotice = (
        <Alert variant="destructive" className="max-w-md">
          <AlertTriangle />
          <AlertDescription>{t('mobileNotOptimized')}</AlertDescription>
        </Alert>
      );

      if (isIosDevice) {
        mobileNotice = (
          <div className="flex flex-col items-center gap-2">
            <Button asChild>
              <a href={IOS_APP_URL} target="_blank" rel="noopener noreferrer">
                {t('getIosApp')}
              </a>
            </Button>
            <span className="text-sm text-muted-foreground">
              {t('getIosAppDesc')}
            </span>
          </div>
        );
      }

      content = (
        <>
          <div className="flex-col gap-2 h-full w-full hidden lg:flex overflow-auto">
            <PluginSlotRenderer slotId={PluginSlot.HOME_SCREEN} />
          </div>
          <div className="flex flex-col items-center justify-center h-full gap-6 p-8 text-center md:hidden">
            <div className="flex flex-col gap-2">
              <h2 className="text-2xl font-semibold text-foreground">
                {t('welcomeToServer', { name: serverName })}
              </h2>
            </div>
            {mobileNotice}
            <div className="flex flex-col gap-3 text-sm text-muted-foreground">
              <button
                type="button"
                className="flex items-center gap-2"
                onClick={onOpenChannelsClick}
              >
                <span className="text-lg">
                  <ArrowRight />
                </span>
                <span>{t('swipeRightForChannels')}</span>
              </button>
              <button
                type="button"
                className="flex items-center gap-2"
                onClick={onOpenMembersClick}
              >
                <span className="text-lg">
                  <ArrowLeft />
                </span>
                <span>{t('swipeLeftForUsers')}</span>
              </button>
            </div>
          </div>
        </>
      );
    }

    return (
      <main className="flex flex-1 flex-col bg-background relative min-w-0 min-h-0">
        {content}
      </main>
    );
  }
);

export { ContentWrapper };
