import { Dialog } from '@/components/dialogs/dialogs';
import {
  setSelectedDmChannelId,
  toggleChannelMuted
} from '@/features/app/actions';
import {
  useIsChannelMuted,
  useSelectedDmChannelId
} from '@/features/app/hooks';
import {
  openDialog,
  requestConfirmation,
  requestTextInput
} from '@/features/dialogs/actions';
import { markChannelAsRead } from '@/features/server/actions';
import { loadDirectMessages } from '@/features/server/dms/actions';
import {
  useConversation,
  useConversationTitle,
  useUnreadMessagesCount
} from '@/features/server/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { getTrpcError } from '@sharkord/shared';
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

type TDirectMessageContextMenuProps = {
  children: React.ReactNode;
  channelId: number;
};

const DirectMessageContextMenu = memo(
  ({ children, channelId }: TDirectMessageContextMenuProps) => {
    const { t } = useTranslation('sidebar');
    const conversation = useConversation(channelId);
    const title = useConversationTitle(channelId);
    const unreadCount = useUnreadMessagesCount(channelId);
    const isMuted = useIsChannelMuted(channelId);
    const selectedDmChannelId = useSelectedDmChannelId();

    const group = conversation?.group;

    // a conversation gone from the list should not stay open behind it
    const deselect = useCallback(() => {
      if (selectedDmChannelId === channelId) {
        setSelectedDmChannelId(undefined);
      }
    }, [channelId, selectedDmChannelId]);

    const onMarkAsReadClick = useCallback(() => {
      markChannelAsRead(channelId);
    }, [channelId]);

    const onToggleMuteClick = useCallback(() => {
      toggleChannelMuted(channelId);
    }, [channelId]);

    const onAddFriendsClick = useCallback(() => {
      openDialog(Dialog.GROUP_DM, {
        channelId,
        memberIds: group?.memberIds ?? []
      });
    }, [channelId, group]);

    const onRenameClick = useCallback(async () => {
      const name = await requestTextInput({
        title: t('renameGroupTitle'),
        message: t('renameGroupMsg'),
        confirmLabel: t('renameLabel'),
        allowEmpty: true
      });

      if (name === null) {
        return;
      }

      const trimmed = name?.trim();

      try {
        const trpc = getTRPCClient();

        await trpc.dms.renameGroup.mutate({
          channelId,
          name: trimmed || null
        });
        await loadDirectMessages();
      } catch (error) {
        toast.error(getTrpcError(error, t('failedRenameGroup')));
      }
    }, [channelId, t]);

    const onCloseClick = useCallback(async () => {
      try {
        const trpc = getTRPCClient();

        await trpc.dms.close.mutate({ channelId });
        deselect();
        await loadDirectMessages();
      } catch (error) {
        toast.error(getTrpcError(error, t('failedCloseDM')));
      }
    }, [channelId, deselect, t]);

    const onLeaveClick = useCallback(async () => {
      const choice = await requestConfirmation({
        title: t('leaveGroupTitle', { name: title }),
        message: t('leaveGroupMsg'),
        confirmLabel: t('leaveGroup'),
        cancelLabel: t('cancel', { ns: 'common' }),
        variant: 'danger'
      });

      if (!choice) {
        return;
      }

      try {
        const trpc = getTRPCClient();

        await trpc.dms.leaveGroup.mutate({ channelId });
        deselect();
        await loadDirectMessages();
      } catch (error) {
        toast.error(getTrpcError(error, t('failedLeaveGroup')));
      }
    }, [channelId, deselect, t, title]);

    return (
      <ContextMenu>
        <ContextMenuTrigger>{children}</ContextMenuTrigger>
        <ContextMenuContent>
          <ContextMenuLabel className="max-w-56 truncate">
            {title}
          </ContextMenuLabel>
          <ContextMenuSeparator />
          {unreadCount > 0 && (
            <ContextMenuItem onClick={onMarkAsReadClick}>
              {t('markAsRead')}
            </ContextMenuItem>
          )}
          <ContextMenuItem onClick={onToggleMuteClick}>
            {isMuted ? t('unmuteConversation') : t('muteConversation')}
          </ContextMenuItem>
          {group && (
            <>
              <ContextMenuSeparator />
              <ContextMenuItem onClick={onAddFriendsClick}>
                {t('addFriendsToGroup')}
              </ContextMenuItem>
              <ContextMenuItem onClick={onRenameClick}>
                {t('renameGroup')}
              </ContextMenuItem>
            </>
          )}
          <ContextMenuSeparator />
          {group ? (
            <ContextMenuItem variant="destructive" onClick={onLeaveClick}>
              {t('leaveGroup')}
            </ContextMenuItem>
          ) : (
            <ContextMenuItem onClick={onCloseClick}>
              {t('closeDM')}
            </ContextMenuItem>
          )}
        </ContextMenuContent>
      </ContextMenu>
    );
  }
);

export { DirectMessageContextMenu };
