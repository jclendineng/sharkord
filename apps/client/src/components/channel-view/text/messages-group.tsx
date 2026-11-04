import { PluginAvatar } from '@/components/plugin-avatar';
import { RelativeTime } from '@/components/relative-time';
import { UserAvatar } from '@/components/user-avatar';
import { useIsUserBlocked } from '@/features/server/dms/hooks';
import { isPendingMessage } from '@/features/server/messages/actions';
import { usePluginMetadata } from '@/features/server/plugins/hooks';
import { useIsOwnUser, useUserById } from '@/features/server/users/hooks';
import { cn } from '@/lib/utils';
import {
  DELETED_USER_IDENTITY_AND_NAME,
  type TJoinedMessage
} from '@sharkord/shared';
import { format } from 'date-fns';
import { memo } from 'react';
import { BlockedMessages } from './blocked-messages';
import { areGroupsEqual } from './helpers';
import { useMessageAuthorName } from './hooks/use-message-author-name';
import { Message } from './message';
import { MessageReplyPreviewWrapper } from './message-reply-preview-wrapper';

type TMessagesGroupProps = {
  group: TJoinedMessage[];
  disableActions?: boolean;
  disableFiles?: boolean;
  disableReactions?: boolean;
  onReplyMessageSelect?: (message: TJoinedMessage) => void;
  replyTargetMessageId?: number;
  activeThreadMessageId?: number;
  editingMessageId?: number;
  onEditComplete?: () => void;
};

const MessagesGroup = memo(
  ({
    group,
    disableActions,
    disableFiles,
    disableReactions,
    onReplyMessageSelect,
    replyTargetMessageId,
    activeThreadMessageId,
    editingMessageId,
    onEditComplete
  }: TMessagesGroupProps) => {
    const firstMessage = group[0];
    const pluginMetadata = usePluginMetadata(firstMessage.pluginId);
    const user = useUserById(firstMessage.userId);
    const date = new Date(firstMessage.createdAt);
    const isOwnUser = useIsOwnUser(firstMessage.userId);
    // a plugin or a webhook has no user id, and can't be blocked
    const isBlocked = useIsUserBlocked(firstMessage.userId ?? -1);
    const authorName = useMessageAuthorName(firstMessage);
    const isDeletedUser = user?.name === DELETED_USER_IDENTITY_AND_NAME;
    const isPluginMessage = !!firstMessage.pluginId;
    const webhookName = firstMessage.webhookName;
    const isBotMessage = isPluginMessage || !!webhookName;

    const isReplyToMessage =
      group.length === 1 && !!firstMessage.replyToMessageId;

    const groupContent = (
      <div className="flex min-w-0 max-w-dvw gap-1 pl-2 pt-2 pr-2">
        {isBotMessage ? (
          <PluginAvatar
            name={pluginMetadata?.name ?? webhookName ?? undefined}
            avatarUrl={pluginMetadata?.avatarUrl}
            className="h-10 w-10"
          />
        ) : (
          <UserAvatar userId={user!.id} className="h-10 w-10" showUserPopover />
        )}
        <div className="flex min-w-0 flex-col w-full">
          <div className="flex gap-2 items-baseline pl-1 select-none">
            <span
              className={cn(
                isOwnUser && 'font-bold',
                isDeletedUser && 'line-through text-muted-foreground',
                isBotMessage && 'text-primary-text/80'
              )}
            >
              {authorName}
            </span>
            {isBotMessage && (
              <span className="inline-flex items-center rounded-sm bg-primary/10 px-1.5 py-0.5 text-[11px] font-medium text-primary-text/60 uppercase tracking-wide">
                bot
              </span>
            )}
            <RelativeTime date={date}>
              {(relativeTime) => (
                <span
                  className="text-primary-text/60 text-xs"
                  title={format(date, 'PPpp')}
                >
                  {relativeTime}
                </span>
              )}
            </RelativeTime>
          </div>
          <div className="flex min-w-0 flex-col">
            {group.map((message) => (
              <div
                key={message.id}
                id={`message-${message.id}`}
                className={cn(
                  'rounded-md transition-colors duration-1000',
                  isPendingMessage(message) && 'opacity-55'
                )}
              >
                <Message
                  message={message}
                  disableActions={disableActions || isPendingMessage(message)}
                  disableFiles={disableFiles}
                  disableReactions={disableReactions}
                  onReplyMessageSelect={onReplyMessageSelect}
                  isInlineReplyTarget={message.id === replyTargetMessageId}
                  isActiveThread={message.id === activeThreadMessageId}
                  editingMessageId={editingMessageId}
                  onEditComplete={onEditComplete}
                />
              </div>
            ))}
          </div>
        </div>
      </div>
    );

    let content = groupContent;

    if (isReplyToMessage) {
      content = (
        <MessageReplyPreviewWrapper message={firstMessage}>
          {groupContent}
        </MessageReplyPreviewWrapper>
      );
    }

    if (isBlocked) {
      return <BlockedMessages count={group.length}>{content}</BlockedMessages>;
    }

    return content;
  },
  areGroupsEqual
);

export { MessagesGroup };
