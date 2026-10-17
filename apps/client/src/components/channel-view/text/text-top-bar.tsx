import { PluginSlotRenderer } from '@/components/plugin-slot-renderer';
import { setMobileDrawer, toggleChannelMuted } from '@/features/app/actions';
import { useIsChannelMuted } from '@/features/app/hooks';
import { useChannelById } from '@/features/server/channels/hooks';
import { useConversation, useConversationTitle } from '@/features/server/hooks';
import { MobileDrawer } from '@/types';
import { ChannelType, PluginSlot } from '@sharkord/shared';
import { IconButton, Tooltip } from '@sharkord/ui';
import {
  BellOff,
  Hash,
  Menu,
  MessageCircleMore,
  Users,
  Volume2,
  X
} from 'lucide-react';
import { memo, useCallback, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import { PinnedMessagesPopover } from './pinned-messages-popover';

type TTextTopbarProps = {
  onScrollToMessage: (messageId: number) => Promise<void>;
  channelId: number;
  onClose?: () => void;
};

const TextTopbar = memo(
  ({ onScrollToMessage, channelId, onClose }: TTextTopbarProps) => {
    const { t } = useTranslation();
    const channel = useChannelById(channelId);
    const isMuted = useIsChannelMuted(channelId);
    const conversation = useConversation(channelId);
    const conversationTitle = useConversationTitle(channelId);

    const onUnmuteClick = useCallback(() => {
      toggleChannelMuted(channelId);
    }, [channelId]);

    const onOpenChannelsClick = useCallback(() => {
      setMobileDrawer(MobileDrawer.CHANNELS);
    }, []);

    const onOpenMembersClick = useCallback(() => {
      setMobileDrawer(MobileDrawer.MEMBERS);
    }, []);

    const pluginProps = useMemo(() => ({ channelId }), [channelId]);

    const info = useMemo(() => {
      if (channel?.isDm) {
        const group = conversation?.group;

        return {
          name: conversationTitle ?? t('directMessage'),
          topic: group
            ? t('groupMembers', { count: group.memberIds.length + 1 })
            : undefined
        };
      }

      return {
        name: channel?.name,
        topic: channel?.topic
      };
    }, [channel, conversation, conversationTitle, t]);

    const getIcon = useCallback(() => {
      if (conversation?.group) {
        return <Users className="inline-block text-muted-foreground h-4 w-4" />;
      }

      if (channel?.isDm) {
        return (
          <MessageCircleMore className="inline-block text-muted-foreground h-4 w-4" />
        );
      }

      if (channel?.type === ChannelType.TEXT) {
        return <Hash className="inline-block text-muted-foreground h-4 w-4" />;
      }

      if (channel?.type === ChannelType.VOICE) {
        return (
          <Volume2 className="inline-block text-muted-foreground h-4 w-4" />
        );
      }

      return null;
    }, [channel, conversation]);

    return (
      <div className="flex h-12 border-b border-border bg-card w-auto overflow-hidden">
        <div className="flex w-full items-center justify-between px-4">
          <div className="flex items-center gap-2 min-w-0">
            {!onClose && (
              <IconButton
                onClick={onOpenChannelsClick}
                icon={Menu}
                variant="ghost"
                className="md:hidden -ml-1 mr-1"
                aria-label={t('openChannelList')}
              />
            )}
            {getIcon()}
            <span className="font-bold truncate max-w-40">{info.name}</span>
            {info.topic && (
              <span className="text-xs text-muted-foreground truncate">
                {info.topic}
              </span>
            )}
          </div>
          <div className="flex items-center gap-2">
            <PluginSlotRenderer
              slotId={PluginSlot.CHANNEL_HEADER}
              props={pluginProps}
            />

            {isMuted && (
              <Tooltip content={t('channelMutedTooltip')}>
                <IconButton
                  icon={BellOff}
                  size="sm"
                  variant="ghost"
                  onClick={onUnmuteClick}
                />
              </Tooltip>
            )}
            <PinnedMessagesPopover onScrollToMessage={onScrollToMessage} />
            {!onClose && (
              <IconButton
                onClick={onOpenMembersClick}
                icon={Users}
                variant="ghost"
                size="sm"
                className="lg:hidden"
                aria-label={t('openMemberList')}
              />
            )}
            {onClose && (
              <IconButton
                onClick={onClose}
                icon={X}
                variant="ghost"
                size="sm"
              />
            )}
          </div>
        </div>
      </div>
    );
  }
);

export { TextTopbar };
