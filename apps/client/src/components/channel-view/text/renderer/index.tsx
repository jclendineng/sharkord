import { ErrorBoundary } from '@/components/error-boundary';
import { PluginSlotRenderer } from '@/components/plugin-slot-renderer';
import { RelativeTime } from '@/components/relative-time';
import { requestConfirmation } from '@/features/dialogs/actions';
import { useOwnUserId, useUserById } from '@/features/server/users/hooks';
import { useFileTokensVersion } from '@/helpers/file-tokens';
import { getFileUrl } from '@/helpers/get-file-url';
import { getRenderedUsername } from '@/helpers/get-rendered-username';
import { getTRPCClient } from '@/lib/trpc';
import { cn } from '@/lib/utils';
import {
  FileCategory,
  getFileCategory,
  PluginSlot,
  type TJoinedMessage
} from '@sharkord/shared';
import { Tooltip } from '@sharkord/ui';
import { memo, useCallback, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import { AudioCard } from '../audio-card';
import { FileCard } from '../file-card';
import { MessageReactions } from '../message-reactions';
import { YoutubeOverride } from '../overrides/youtube';
import { Poll } from '../poll';
import { RulesNote } from '../rules-note';
import {
  getIsEmojiOnly,
  getParsedMessageHtml,
  getYoutubeVideoIds
} from './content-cache';
import { extractMessageOpenGraph, isMediaLinkOnly } from './helpers';
import { Media } from './media';
import { extractMessageMedia } from './media-cache';
import { MessageRenderFallback } from './message-render-fallback';
import { OpenGraph } from './open-graph';

type TMessageRendererProps = {
  message: TJoinedMessage;
  disableFiles?: boolean;
  disableReactions?: boolean;
};

const MessageRenderer = memo(
  ({ message, disableFiles, disableReactions }: TMessageRendererProps) => {
    const { t } = useTranslation();
    const ownUserId = useOwnUserId();
    const editedByUser = useUserById(message.editedBy ?? -1);
    const isOwnMessage = useMemo(
      () => message.userId === ownUserId,
      [message.userId, ownUserId]
    );

    // signed links on screen run out after a while, this draws them again with fresh ones
    const fileTokensVersion = useFileTokensVersion();

    const emojiOnly = useMemo(() => getIsEmojiOnly(message), [message]);

    const pluginProps = useMemo(
      () => ({ messageId: message.id, channelId: message.channelId }),
      [message.id, message.channelId]
    );

    const messageHtml = useMemo(() => getParsedMessageHtml(message), [message]);

    const onRemoveFileClick = useCallback(
      async (fileId: number) => {
        if (!fileId) return;

        const choice = await requestConfirmation({
          title: t('deleteFileTitle'),
          message: t('deleteFileMsg'),
          confirmLabel: t('deleteLabel')
        });

        if (!choice) return;

        const trpc = getTRPCClient();

        try {
          await trpc.files.delete.mutate({
            fileId
          });

          toast.success(t('fileDeleted'));
        } catch {
          toast.error(t('failedDeleteFile'));
        }
      },
      [t]
    );

    // the cache keeps what it found per message, the attachments' links are drawn here so a
    // fresh signed link reaches them
    const allMedia = useMemo(
      () =>
        extractMessageMedia(message).map((item) =>
          item.file ? { ...item, url: getFileUrl(item.file) } : item
        ),
      // getFileUrl reads the fresh links, the version is how they reach this memo
      // eslint-disable-next-line react-hooks/exhaustive-deps
      [message, fileTokensVersion]
    );

    const youtubeVideoIds = useMemo(
      () => getYoutubeVideoIds(message),
      [message]
    );

    const openGraphPreviews = useMemo(
      () => extractMessageOpenGraph(message, allMedia),
      [message, allMedia]
    );

    const hidesText = useMemo(
      () => isMediaLinkOnly(message.content, allMedia),
      [message.content, allMedia]
    );

    return (
      <div className="flex flex-col gap-1">
        <div
          className={cn(
            'prose max-w-full wrap-break-word msg-content',
            emojiOnly && 'emoji-only',
            message.editedAt && 'msg-edited',
            hidesText && 'hidden'
          )}
        >
          <ErrorBoundary
            fallback={(error, reset) => (
              <MessageRenderFallback error={error} reset={reset} />
            )}
          >
            {messageHtml}
          </ErrorBoundary>
          {message.editedAt && (
            <Tooltip
              content={
                <div className="flex flex-col gap-1">
                  <RelativeTime date={new Date(message.editedAt)}>
                    {(relativeTime) => (
                      <span className="text-secondary text-xs">
                        {editedByUser
                          ? getRenderedUsername(editedByUser)
                          : t('unknownUser')}{' '}
                        {relativeTime}
                      </span>
                    )}
                  </RelativeTime>
                </div>
              }
            >
              <span className="msg-edit ml-1 text-xs text-muted-foreground">
                {t('edited')}
              </span>
            </Tooltip>
          )}
        </div>

        {youtubeVideoIds.map((videoId) => (
          <YoutubeOverride key={videoId} videoId={videoId} />
        ))}
        <Media media={allMedia} />
        <OpenGraph previews={openGraphPreviews} />

        {message.sticker && (
          <Tooltip content={message.sticker.name}>
            <img
              src={getFileUrl(message.sticker.file)}
              alt={message.sticker.name}
              className="h-40 w-40 object-contain"
              loading="lazy"
            />
          </Tooltip>
        )}

        {message.poll && (
          <Poll
            messageId={message.id}
            authorId={message.userId}
            poll={message.poll}
          />
        )}

        {!disableReactions && (
          <MessageReactions
            reactions={message.reactions}
            messageId={message.id}
          />
        )}

        <RulesNote messageId={message.id} />

        <PluginSlotRenderer
          slotId={PluginSlot.MESSAGE_FOOTER}
          props={pluginProps}
        />

        {message.files.length > 0 && !disableFiles && (
          <div className="flex gap-1 flex-wrap">
            {message.files.map((file) =>
              getFileCategory(file.extension) === FileCategory.AUDIO ? (
                <AudioCard
                  key={file.id}
                  name={file.originalName}
                  size={file.size}
                  src={getFileUrl(file)}
                  onRemove={
                    isOwnMessage ? () => onRemoveFileClick(file.id) : undefined
                  }
                />
              ) : (
                <FileCard
                  key={file.id}
                  name={file.originalName}
                  extension={file.extension}
                  size={file.size}
                  onRemove={
                    isOwnMessage ? () => onRemoveFileClick(file.id) : undefined
                  }
                  href={getFileUrl(file)}
                />
              )
            )}
          </div>
        )}
      </div>
    );
  }
);

export { MessageRenderer };
