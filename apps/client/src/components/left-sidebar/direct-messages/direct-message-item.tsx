import { DirectMessageContextMenu } from '@/components/context-menus/direct-message';
import { UnreadCount } from '@/components/unread-count';
import { UserAvatar } from '@/components/user-avatar';
import { setSelectedDmChannelId } from '@/features/app/actions';
import { useIsChannelMuted } from '@/features/app/hooks';
import {
  useConversationTitle,
  useUnreadMessagesCount
} from '@/features/server/hooks';
import { useOwnUserId } from '@/features/server/users/hooks';
import { cn } from '@/lib/utils';
import { TestId, type TDirectMessageConversation } from '@sharkord/shared';
import { BellOff } from 'lucide-react';
import { memo, useCallback, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import { GroupAvatar } from './group-avatar';

type TDirectMessageItemProps = {
  dm: TDirectMessageConversation;
  selected: boolean;
};

const DirectMessageItem = memo(({ dm, selected }: TDirectMessageItemProps) => {
  const { t } = useTranslation('sidebar');
  const title = useConversationTitle(dm.channelId);
  const unreadCount = useUnreadMessagesCount(dm.channelId);
  const isMuted = useIsChannelMuted(dm.channelId);
  const ownUserId = useOwnUserId();

  const onSelect = useCallback(() => {
    setSelectedDmChannelId(dm.channelId);
  }, [dm.channelId]);

  // the newest message, yours marked as such. an empty one carried only attachments
  const preview = useMemo(() => {
    const text = dm.lastMessagePreview;

    if (text === null) {
      if (dm.group) {
        return t('groupMembers', { count: dm.group.memberIds.length + 1 });
      }

      return undefined;
    }

    const body = text || t('sentAttachment');

    if (dm.lastMessageUserId === ownUserId) {
      return t('youPreview', { text: body });
    }

    return body;
  }, [dm, ownUserId, t]);

  if (!title) {
    return null;
  }

  return (
    <DirectMessageContextMenu channelId={dm.channelId}>
      <button
        data-testid={TestId.DM_ITEM}
        type="button"
        className={cn(
          'flex w-full items-center gap-2 rounded px-2 py-1.5 text-sm text-muted-foreground hover:bg-accent hover:text-accent-foreground',
          selected && 'bg-accent text-accent-foreground',
          unreadCount > 0 && !isMuted && 'text-foreground'
        )}
        onClick={onSelect}
      >
        {dm.group ? (
          <GroupAvatar className="h-8 w-8" />
        ) : (
          <UserAvatar userId={dm.userId} className="h-8 w-8" showUserPopover />
        )}
        <div className="flex min-w-0 flex-1 flex-col text-left">
          <span
            className={cn(
              'truncate',
              unreadCount > 0 && !isMuted && 'font-semibold'
            )}
          >
            {title}
          </span>
          {preview && (
            <span className="truncate text-xs text-muted-foreground">
              {preview}
            </span>
          )}
        </div>
        {isMuted && <BellOff className="h-3.5 w-3.5 shrink-0" />}
        {!isMuted && <UnreadCount count={unreadCount} />}
      </button>
    </DirectMessageContextMenu>
  );
});

export { DirectMessageItem };
