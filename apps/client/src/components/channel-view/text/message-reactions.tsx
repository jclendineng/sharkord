import { Emoji } from '@/components/emoji';
import { useOwnUserId } from '@/features/server/users/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { cn } from '@/lib/utils';
import {
  getTrpcError,
  type TFile,
  type TJoinedMessageReaction
} from '@sharkord/shared';
import { Button, Tooltip } from '@sharkord/ui';
import { memo, useCallback, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import { useReactorNames } from './hooks/use-reactor-names';

type TTooltipPreviewProps = {
  emojiName: string;
  emojiSlot: React.ReactNode;
  reacters: string;
};

const TooltipPreview = memo(
  ({ emojiName, emojiSlot, reacters }: TTooltipPreviewProps) => {
    const { t } = useTranslation('common');

    return (
      <div className="flex items-center gap-2 max-w-xs wrap-break-word whitespace-pre-wrap text-sm">
        <div className="flex items-center flex-col">
          {emojiSlot}
          <span className="text-[11px]">:{emojiName}:</span>
        </div>
        <span className="text-xs">{t('wasReactedBy', { reacters })}</span>
      </div>
    );
  }
);

type TReactionProps = {
  emoji: string;
  count: number;
  isUserReacted: boolean;
  onSelect: (emoji: string) => void;
  file: TFile | null;
  userIds: number[];
  pluginIds: string[];
};

const Reaction = memo(
  ({
    emoji,
    count,
    isUserReacted,
    onSelect,
    file,
    userIds,
    pluginIds
  }: TReactionProps) => {
    const handleClick = useCallback(() => onSelect(emoji), [onSelect, emoji]);
    const tooltipContent = useReactorNames(userIds, pluginIds);

    return (
      <Tooltip
        content={
          <TooltipPreview
            emojiName={emoji}
            reacters={tooltipContent}
            emojiSlot={
              <Emoji
                emoji={emoji}
                file={file}
                className="w-10 h-10"
                nativeEmojiClassName="text-[28px]"
              />
            }
          />
        }
      >
        <Button
          size="sm"
          variant="outline"
          onClick={handleClick}
          className={cn(
            'flex items-center gap-1 h-9',
            isUserReacted ? 'border-border' : 'border-none'
          )}
        >
          <Emoji emoji={emoji} file={file} />
          <span className="font-medium tabular-nums">{count}</span>
        </Button>
      </Tooltip>
    );
  }
);

type TMessageReactionsProps = {
  messageId: number;
  reactions: TJoinedMessageReaction[];
};

type TAggregatedReaction = {
  emoji: string;
  count: number;
  userIds: number[];
  pluginIds: string[];
  isUserReacted: boolean;
  createdAt: number;
  file: TFile | null;
};

// a click shows at once. it holds while the reactions are still the ones it was made on, or
// once the server agrees with it, so a late update can't flip it back and forth
type TPendingReaction = {
  isMine: boolean;
  base: TJoinedMessageReaction[];
};

const isOwnReaction = (
  reactions: TJoinedMessageReaction[],
  emoji: string,
  ownUserId: number
) =>
  reactions.some(
    (reaction) => reaction.emoji === emoji && reaction.userId === ownUserId
  );

const MessageReactions = memo(
  ({ messageId, reactions }: TMessageReactionsProps) => {
    const { t } = useTranslation();
    const ownUserId = useOwnUserId();
    const [pending, setPending] = useState<Record<string, TPendingReaction>>(
      {}
    );

    const handleReactionClick = useCallback(
      async (emoji: string) => {
        if (!ownUserId) return;

        const entry = pending[emoji];
        const isMine =
          entry && entry.base === reactions
            ? entry.isMine
            : isOwnReaction(reactions, emoji, ownUserId);

        setPending((current) => ({
          ...current,
          [emoji]: { isMine: !isMine, base: reactions }
        }));

        try {
          const trpc = getTRPCClient();

          await trpc.messages.toggleReaction.mutate({
            messageId,
            emoji
          });
        } catch (error) {
          setPending((current) => {
            const { [emoji]: _, ...rest } = current;

            return rest;
          });

          toast.error(getTrpcError(error, t('failedToggleReaction')));
        }
      },
      [messageId, ownUserId, pending, reactions, t]
    );

    const aggregatedReactions = useMemo((): TAggregatedReaction[] => {
      const reactionMap = new Map<string, TAggregatedReaction>();

      reactions.forEach((reaction) => {
        if (!reactionMap.has(reaction.emoji)) {
          reactionMap.set(reaction.emoji, {
            emoji: reaction.emoji,
            count: 0,
            userIds: [],
            pluginIds: [],
            isUserReacted: false,
            createdAt: reaction.createdAt,
            file: reaction.file
          });
        }

        const aggregated = reactionMap.get(reaction.emoji)!;

        aggregated.count++;

        if (reaction.pluginId) {
          aggregated.pluginIds.push(reaction.pluginId);
        } else if (reaction.userId !== null) {
          aggregated.userIds.push(reaction.userId);
        }

        if (ownUserId && reaction.userId === ownUserId) {
          aggregated.isUserReacted = true;
        }
      });

      if (ownUserId) {
        Object.entries(pending).forEach(([emoji, entry]) => {
          const isMineOnServer = isOwnReaction(reactions, emoji, ownUserId);

          if (entry.base !== reactions || entry.isMine === isMineOnServer) {
            return;
          }

          const aggregated = reactionMap.get(emoji);

          if (entry.isMine) {
            if (aggregated) {
              aggregated.count++;
              aggregated.userIds.push(ownUserId);
              aggregated.isUserReacted = true;
            } else {
              reactionMap.set(emoji, {
                emoji,
                count: 1,
                userIds: [ownUserId],
                pluginIds: [],
                isUserReacted: true,
                createdAt: Date.now(),
                file: null
              });
            }
          } else if (aggregated) {
            aggregated.count--;
            aggregated.userIds = aggregated.userIds.filter(
              (userId) => userId !== ownUserId
            );
            aggregated.isUserReacted = false;

            if (aggregated.count === 0) {
              reactionMap.delete(emoji);
            }
          }
        });
      }

      // sort by first reaction createdAt desc
      return Array.from(reactionMap.values()).sort(
        (a, b) => b.createdAt - a.createdAt
      );
    }, [reactions, ownUserId, pending]);

    if (!aggregatedReactions.length) return null;

    return (
      <div className="mt-1 flex flex-wrap gap-1">
        {aggregatedReactions.map((reaction) => (
          <Reaction
            key={reaction.emoji}
            emoji={reaction.emoji}
            count={reaction.count}
            userIds={reaction.userIds}
            pluginIds={reaction.pluginIds}
            isUserReacted={reaction.isUserReacted}
            onSelect={handleReactionClick}
            file={reaction.file}
          />
        ))}
      </div>
    );
  }
);

export { MessageReactions };
