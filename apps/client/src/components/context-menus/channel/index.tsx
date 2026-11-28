import { ServerScreen } from '@/components/server-screens/screens';
import {
  openVoiceChatSidebar,
  toggleChannelMuted
} from '@/features/app/actions';
import { useIsChannelMuted } from '@/features/app/hooks';
import { requestConfirmation } from '@/features/dialogs/actions';
import { openServerScreen } from '@/features/server-screens/actions';
import { markChannelAsRead } from '@/features/server/actions';
import { useChannelById } from '@/features/server/channels/hooks';
import { useCan, useUnreadMessagesCount } from '@/features/server/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { ChannelType, getTrpcError, Permission } from '@sharkord/shared';
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuLabel,
  ContextMenuSeparator,
  ContextMenuTrigger
} from '@sharkord/ui';
import { memo, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TChannelContextMenuProps = {
  children: React.ReactNode;
  channelId: number;
};

const ChannelContextMenu = memo(
  ({ children, channelId }: TChannelContextMenuProps) => {
    const { t } = useTranslation('sidebar');
    const can = useCan();
    const channel = useChannelById(channelId);

    const canManageChannels = can(Permission.MANAGE_CHANNELS);
    const canEditChannel = can([
      Permission.MANAGE_CHANNELS,
      Permission.MANAGE_CHANNEL_PERMISSIONS
    ]);
    const isVoiceChannel = channel?.type === ChannelType.VOICE;
    const isMuted = useIsChannelMuted(channelId);
    const unreadCount = useUnreadMessagesCount(channelId);

    const onOpenChat = useCallback(() => {
      openVoiceChatSidebar(channelId);
    }, [channelId]);

    const onMarkAsReadClick = useCallback(() => {
      markChannelAsRead(channelId);
    }, [channelId]);

    // the apps' clone: the same name, kind and category, private and with its topic if it was
    const onDuplicateClick = useCallback(async () => {
      if (!channel?.categoryId) return;

      try {
        const trpc = getTRPCClient();
        const newChannelId = await trpc.channels.add.mutate({
          type: channel.type as ChannelType,
          name: channel.name,
          categoryId: channel.categoryId
        });

        if (channel.private || channel.topic) {
          await trpc.channels.update.mutate({
            channelId: newChannelId,
            name: channel.name,
            topic: channel.topic,
            private: channel.private
          });
        }
      } catch (error) {
        toast.error(getTrpcError(error, t('failedDuplicateChannel')));
      }
    }, [channel, t]);

    const onToggleMuteClick = useCallback(() => {
      toggleChannelMuted(channelId);
    }, [channelId]);

    const onDeleteClick = useCallback(async () => {
      const choice = await requestConfirmation({
        title: t('deleteChannelTitle'),
        message: t('deleteChannelMsg'),
        confirmLabel: t('deleteLabel'),
        cancelLabel: t('cancel', { ns: 'common' })
      });

      if (!choice) return;

      const trpc = getTRPCClient();

      try {
        await trpc.channels.delete.mutate({ channelId });

        toast.success(t('channelDeleted'));
      } catch {
        toast.error(t('failedDeleteChannel'));
      }
    }, [channelId, t]);

    const onEditClick = useCallback(() => {
      openServerScreen(ServerScreen.CHANNEL_SETTINGS, { channelId });
    }, [channelId]);

    return (
      <ContextMenu>
        <ContextMenuTrigger>{children}</ContextMenuTrigger>
        <ContextMenuContent>
          <ContextMenuLabel>{channel?.name}</ContextMenuLabel>
          <ContextMenuSeparator />
          {isVoiceChannel && (
            <ContextMenuItem onClick={onOpenChat}>
              {t('openChat')}
            </ContextMenuItem>
          )}
          {unreadCount > 0 && (
            <ContextMenuItem onClick={onMarkAsReadClick}>
              {t('markAsRead')}
            </ContextMenuItem>
          )}
          <ContextMenuItem onClick={onToggleMuteClick}>
            {isMuted ? t('unmuteChannel') : t('muteChannel')}
          </ContextMenuItem>
          {canEditChannel && (
            <>
              <ContextMenuSeparator />
              <ContextMenuItem onClick={onEditClick}>
                {t('editLabel')}
              </ContextMenuItem>
            </>
          )}
          {canManageChannels && (
            <ContextMenuItem onClick={onDuplicateClick}>
              {t('duplicateChannel')}
            </ContextMenuItem>
          )}
          {canManageChannels && (
            <ContextMenuItem variant="destructive" onClick={onDeleteClick}>
              {t('deleteLabel')}
            </ContextMenuItem>
          )}
        </ContextMenuContent>
      </ContextMenu>
    );
  }
);

export { ChannelContextMenu };
