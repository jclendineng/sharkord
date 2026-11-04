import {
  browserNotificationsForDmsSelector,
  browserNotificationsForMentionsSelector,
  browserNotificationsForRepliesSelector,
  browserNotificationsSelector,
  isChannelMutedSelector,
  threadSidebarDataSelector
} from '@/features/app/selectors';
import { store } from '@/features/store';
import { getFileUrl } from '@/helpers/get-file-url';
import { playSound } from '@/helpers/sounds';
import {
  getPlainTextFromHtml,
  hasMention,
  TYPING_MS,
  type TJoinedMessage
} from '@sharkord/shared';
import { markChannelAsRead } from '../actions';
import {
  channelByIdSelector,
  isChannelTextVisibleByIdSelector
} from '../channels/selectors';
import { pluginMetadataByIdSelector } from '../plugins/selectors';
import { serverSliceActions } from '../slice';
import { SoundType } from '../types';
import {
  ownUserIdSelector,
  ownUserRoleIdsSelector,
  userByIdSelector
} from '../users/selectors';
import {
  isChannelDetachedSelector,
  messagesByChannelIdSelector,
  messagesMapSelector,
  threadMessagesMapSelector
} from './selectors';

const sendBrowserNotification = (
  message: TJoinedMessage,
  channelId: number,
  isDm = false
) => {
  if (!('Notification' in window) || Notification.permission !== 'granted') {
    return;
  }

  const state = store.getState();

  const user = userByIdSelector(state, message.userId);
  const plugin = pluginMetadataByIdSelector(state, message.pluginId);
  const channel = channelByIdSelector(state, channelId);
  const isPluginMessage = !!message.pluginId;

  if (!user || !channel) {
    return;
  }

  const authorName = isPluginMessage && plugin ? plugin.name : user.name;
  const textContent = getPlainTextFromHtml(message.content ?? '');

  const title = isDm
    ? `${authorName} (DM)`
    : `${authorName} in #${channel?.name ?? 'unknown'}`;

  const body = textContent ? textContent : 'Sent an attachment';
  const icon = user?.avatar ? getFileUrl(user.avatar) : undefined;

  new Notification(title, { body, icon });
};

const typingTimeouts: { [key: string]: NodeJS.Timeout } = {};

const getTypingKey = (channelId: number, userId: number) =>
  `${channelId}-${userId}`;

export const setChannelMessages = (
  channelId: number,
  messages: TJoinedMessage[],
  detached: boolean
) => {
  store.dispatch(
    serverSliceActions.setChannelMessages({ channelId, messages, detached })
  );
};

export const trimChannelMessages = (channelId: number) => {
  store.dispatch(serverSliceActions.trimChannelMessages(channelId));
};

export const addMessages = (
  channelId: number,
  messages: TJoinedMessage[],
  isSubscriptionMessage = false
) => {
  const rootMessages = messages.filter((m) => !m.parentMessageId);
  const threadReplies = messages.filter((m) => !!m.parentMessageId);

  if (isSubscriptionMessage) {
    rootMessages.forEach((message) =>
      replacePendingMessage(channelId, message)
    );
  }

  if (rootMessages.length > 0) {
    store.dispatch(
      serverSliceActions.addMessages({
        channelId,
        messages: rootMessages,
        isLive: isSubscriptionMessage
      })
    );
  }

  const repliesByParent = new Map<number, TJoinedMessage[]>();

  for (const reply of threadReplies) {
    const parentId = reply.parentMessageId!;

    if (!repliesByParent.has(parentId)) {
      repliesByParent.set(parentId, []);
    }

    repliesByParent.get(parentId)!.push(reply);
  }

  for (const [parentMessageId, replies] of repliesByParent) {
    store.dispatch(
      serverSliceActions.addThreadMessages({
        parentMessageId,
        messages: replies
      })
    );
  }

  rootMessages.forEach((message) => {
    if (message.userId) {
      removeTypingUser(channelId, message.userId);
    }
  });

  threadReplies.forEach((message) => {
    if (message.parentMessageId && message.userId) {
      removeThreadTypingUser(message.parentMessageId, message.userId);
    }
  });

  if (isSubscriptionMessage && messages.length > 0) {
    const state = store.getState();
    const ownUserId = ownUserIdSelector(state);
    const hasBrowserNotificationsEnabled = browserNotificationsSelector(state);
    const notificationsForMentionsOnly =
      browserNotificationsForMentionsSelector(state);
    const targetMessage = messages[0];
    const isFromOwnUser =
      targetMessage.userId && ownUserId === targetMessage.userId;

    const isChannelTextVisible = isChannelTextVisibleByIdSelector(
      state,
      channelId
    );

    const isWindowHidden = document?.hidden;
    const isChannelMuted = isChannelMutedSelector(state, channelId);

    if (!isFromOwnUser && !isChannelMuted) {
      const isThreadReply = !!targetMessage.parentMessageId;

      if (isThreadReply) {
        const { isOpen, parentMessageId } = threadSidebarDataSelector(state);

        // only play sound if the user has this thread open
        if (isOpen && parentMessageId === targetMessage.parentMessageId) {
          playSound(SoundType.MESSAGE_RECEIVED);
        }
      } else {
        playSound(SoundType.MESSAGE_RECEIVED);
      }

      // only send browser notifications if the user is not currently viewing this channel
      if (!isChannelTextVisible || isWindowHidden) {
        const channel = channelByIdSelector(state, channelId);
        const isDmChannel = !!channel?.isDm;
        const hasDmNotificationsEnabled =
          browserNotificationsForDmsSelector(state);
        const hasRepliesNotificationsEnabled =
          browserNotificationsForRepliesSelector(state);

        if (isDmChannel && hasDmNotificationsEnabled) {
          sendBrowserNotification(targetMessage, channelId, true);
        } else if (notificationsForMentionsOnly) {
          const ownRoleIds = ownUserRoleIdsSelector(state);
          const isMentioned = hasMention(
            targetMessage.content ?? null,
            ownUserId,
            ownRoleIds
          );

          if (isMentioned) {
            sendBrowserNotification(targetMessage, channelId);
          }
        } else if (hasBrowserNotificationsEnabled) {
          sendBrowserNotification(targetMessage, channelId);
        } else if (hasRepliesNotificationsEnabled) {
          const isReplyToOwnMessage =
            !!targetMessage.replyToMessageId &&
            targetMessage.replyTo?.userId === ownUserId;

          if (isReplyToOwnMessage) {
            sendBrowserNotification(targetMessage, channelId);
          }
        }
      }
    }

    if (isChannelTextVisible && !isFromOwnUser && rootMessages.length > 0) {
      markChannelAsRead(channelId, true);
    }
  }
};

export const updateMessage = (channelId: number, message: TJoinedMessage) => {
  if (message.parentMessageId) {
    store.dispatch(
      serverSliceActions.updateThreadMessage({
        parentMessageId: message.parentMessageId,
        message
      })
    );
  } else {
    store.dispatch(serverSliceActions.updateMessage({ channelId, message }));
  }
};

// a message sent from here shows at once under a negative id, faint and with nothing to act on,
// until the server's own copy arrives and takes its place
let nextPendingMessageId = -1;

export const isPendingMessage = (message: TJoinedMessage) => message.id < 0;

export const addPendingMessage = ({
  channelId,
  content,
  replyTo
}: {
  channelId: number;
  content: string;
  replyTo?: TJoinedMessage;
}): number | undefined => {
  const state = store.getState();
  const ownUserId = ownUserIdSelector(state);
  const existing = messagesMapSelector(state)[channelId];
  const isDetached = isChannelDetachedSelector(state, channelId);

  // a channel not loaded, or showing an older window, has nowhere to put it
  if (!ownUserId || !existing || isDetached) {
    return undefined;
  }

  const id = nextPendingMessageId;
  const newest = existing.at(-1);

  nextPendingMessageId -= 1;

  const message: TJoinedMessage = {
    id,
    content,
    userId: ownUserId,
    pluginId: null,
    webhookName: null,
    pluginComponents: null,
    channelId,
    parentMessageId: null,
    replyToMessageId: replyTo?.id ?? null,
    stickerId: null,
    editable: false,
    metadata: null,
    // never before the newest message, whatever this computer's clock says
    createdAt: Math.max(Date.now(), (newest?.createdAt ?? 0) + 1),
    updatedAt: null,
    pinned: false,
    pinnedAt: null,
    pinnedBy: null,
    editedAt: null,
    editedBy: null,
    files: [],
    reactions: [],
    poll: null,
    sticker: null,
    replyTo: replyTo
      ? {
          id: replyTo.id,
          content: replyTo.content,
          userId: replyTo.userId,
          pluginId: replyTo.pluginId
        }
      : null
  };

  store.dispatch(
    serverSliceActions.addMessages({ channelId, messages: [message] })
  );

  return id;
};

export const removePendingMessage = (channelId: number, messageId: number) => {
  store.dispatch(serverSliceActions.deleteMessage({ channelId, messageId }));
};

// the server said which message it saved: if it has already arrived, the placeholder goes now,
// otherwise its arrival takes the place of one
export const settlePendingMessage = (
  channelId: number,
  pendingId: number,
  messageId: number | null
) => {
  const state = store.getState();
  const messages = messagesByChannelIdSelector(state, channelId);
  const pending = messages.find((message) => message.id === pendingId);

  if (!pending) {
    return;
  }

  const hasArrived = messages.some((message) => message.id === messageId);

  if (messageId === null || hasArrived) {
    removePendingMessage(channelId, pendingId);
  }
};

// your own message arriving live replaces the oldest placeholder in its channel
const replacePendingMessage = (channelId: number, message: TJoinedMessage) => {
  const state = store.getState();
  const ownUserId = ownUserIdSelector(state);

  if (message.userId !== ownUserId || message.parentMessageId) {
    return;
  }

  const messages = messagesByChannelIdSelector(state, channelId);

  if (messages.some((existing) => existing.id === message.id)) {
    return;
  }

  const pending = messages.find(isPendingMessage);

  if (pending) {
    removePendingMessage(channelId, pending.id);
  }
};

export const deleteMessage = (channelId: number, messageId: number) => {
  // delete from both maps, the message could be a thread reply or root
  store.dispatch(serverSliceActions.deleteMessage({ channelId, messageId }));

  const state = store.getState();
  const threadMessagesMap = threadMessagesMapSelector(state);

  for (const parentId in threadMessagesMap) {
    const threadMessages = threadMessagesMap[parentId];

    if (threadMessages?.some((m) => m.id === messageId)) {
      store.dispatch(
        serverSliceActions.deleteThreadMessage({
          parentMessageId: Number(parentId),
          messageId
        })
      );

      break;
    }
  }
};

export const addThreadMessages = (
  parentMessageId: number,
  messages: TJoinedMessage[]
) => {
  store.dispatch(
    serverSliceActions.addThreadMessages({
      parentMessageId,
      messages
    })
  );
};

export const clearThreadMessages = (parentMessageId: number) => {
  store.dispatch(serverSliceActions.clearThreadMessages(parentMessageId));
};

export const addTypingUser = (
  channelId: number,
  userId: number,
  parentMessageId?: number
) => {
  if (parentMessageId) {
    store.dispatch(
      serverSliceActions.addThreadTypingUser({ parentMessageId, userId })
    );

    const timeoutKey = `thread-${parentMessageId}-${userId}`;

    if (typingTimeouts[timeoutKey]) {
      clearTimeout(typingTimeouts[timeoutKey]);
    }

    typingTimeouts[timeoutKey] = setTimeout(() => {
      removeThreadTypingUser(parentMessageId, userId);

      delete typingTimeouts[timeoutKey];
    }, TYPING_MS + 500);
  } else {
    store.dispatch(serverSliceActions.addTypingUser({ channelId, userId }));

    const timeoutKey = getTypingKey(channelId, userId);

    if (typingTimeouts[timeoutKey]) {
      clearTimeout(typingTimeouts[timeoutKey]);
    }

    typingTimeouts[timeoutKey] = setTimeout(() => {
      removeTypingUser(channelId, userId);

      delete typingTimeouts[timeoutKey];
    }, TYPING_MS + 500);
  }
};

export const removeTypingUser = (channelId: number, userId: number) => {
  store.dispatch(serverSliceActions.removeTypingUser({ channelId, userId }));
};

export const removeThreadTypingUser = (
  parentMessageId: number,
  userId: number
) => {
  store.dispatch(
    serverSliceActions.removeThreadTypingUser({ parentMessageId, userId })
  );
};

export const updateReplyCount = (
  channelId: number,
  messageId: number,
  replyCount: number
) => {
  store.dispatch(
    serverSliceActions.updateReplyCount({ channelId, messageId, replyCount })
  );
};
