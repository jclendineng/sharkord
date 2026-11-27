import { TextChannel } from '@/components/channel-view/text';
import { VoiceChannel } from '@/components/channel-view/voice';
import { Dialog } from '@/components/dialogs/dialogs';
import { PluginSlotRenderer } from '@/components/plugin-slot-renderer';
import { setMobileDrawer } from '@/features/app/actions';
import { openDialog } from '@/features/dialogs/actions';
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
import { Button } from '@sharkord/ui';
import { Menu, MessagesSquare, UserPlus, Users } from 'lucide-react';
import { memo, useCallback } from 'react';
import { useTranslation } from 'react-i18next';

type TContentWrapperProps = {
  isDmMode: boolean;
  selectedDmChannelId?: number;
};

const ContentWrapper = memo(
  ({ isDmMode, selectedDmChannelId }: TContentWrapperProps) => {
    const { t } = useTranslation();
    const { t: tSidebar } = useTranslation('sidebar');
    const selectedChannelId = useSelectedChannelId();
    const selectedChannelType = useSelectedChannelType();
    const serverName = useServerName();
    const activeFullscreenPluginId = useActiveFullscreenPluginId();

    const onOpenChannelsClick = useCallback(() => {
      setMobileDrawer(MobileDrawer.CHANNELS);
    }, []);

    const onAddFriendsClick = useCallback(() => {
      openDialog(Dialog.FRIENDS);
    }, []);

    const onNewGroupClick = useCallback(() => {
      openDialog(Dialog.GROUP_DM);
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
            <MessagesSquare className="h-10 w-10" />
            {t('selectDmPrompt')}
            <div className="flex gap-2">
              <Button variant="outline" onClick={onAddFriendsClick}>
                <UserPlus />
                {tSidebar('addFriends')}
              </Button>
              <Button variant="outline" onClick={onNewGroupClick}>
                <Users />
                {tSidebar('newGroup')}
              </Button>
            </div>
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
            <Button variant="outline" onClick={onOpenChannelsClick}>
              <Menu />
              {t('openChannelList')}
            </Button>
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
