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
import { getTRPCClient } from '@/lib/trpc';
import {
  DEFAULT_MESSAGES_LIMIT,
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
    messages.forEach((message) => replacePendingMessage(channelId, message));
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

const storeMessage = (channelId: number, message: TJoinedMessage) => {
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

// reactions toggled here, by message and emoji, that show before the server has them: each says
// whether your own should be there. an update that agrees settles it, one that doesn't yet
// (someone else's reaction arriving first) keeps it showing
const pendingReactions = new Map<number, Map<string, boolean>>();

const withOwnReaction = (
  message: TJoinedMessage,
  emoji: string,
  isMine: boolean,
  ownUserId: number
): TJoinedMessage => {
  const existing = message.reactions.find(
    (reaction) => reaction.emoji === emoji
  );
  const others = message.reactions.filter(
    (reaction) => !(reaction.emoji === emoji && reaction.userId === ownUserId)
  );

  if (!isMine) {
    return { ...message, reactions: others };
  }

  return {
    ...message,
    reactions: [
      ...others,
      {
        messageId: message.id,
        userId: ownUserId,
        pluginId: null,
        emoji,
        fileId: existing?.fileId ?? null,
        file: existing?.file ?? null,
        createdAt: Date.now()
      }
    ]
  };
};

const settlePendingReactions = (message: TJoinedMessage) => {
  const pending = pendingReactions.get(message.id);
  const ownUserId = ownUserIdSelector(store.getState());

  if (!pending || !ownUserId) {
    return message;
  }

  let settled = message;

  for (const [emoji, isMine] of pending) {
    const isMineOnServer = message.reactions.some(
      (reaction) => reaction.emoji === emoji && reaction.userId === ownUserId
    );

    if (isMineOnServer === isMine) {
      pending.delete(emoji);
    } else {
      settled = withOwnReaction(settled, emoji, isMine, ownUserId);
    }
  }

  return settled;
};

const findMessage = (channelId: number, messageId: number) => {
  const state = store.getState();
  const rootMessage = messagesByChannelIdSelector(state, channelId).find(
    (message: TJoinedMessage) => message.id === messageId
  );

  if (rootMessage) {
    return rootMessage;
  }

  const threads = Object.values(threadMessagesMapSelector(state));

  for (const thread of threads) {
    const reply = thread?.find((message) => message.id === messageId);

    if (reply) {
      return reply;
    }
  }

  return undefined;
};

// the pills and the emoji picker both toggle through here, so a reaction shows the moment it is
// picked wherever it came from. a refused toggle goes back to what the message said before
export const toggleReaction = async (
  channelId: number,
  messageId: number,
  emoji: string
) => {
  const ownUserId = ownUserIdSelector(store.getState());
  const message = findMessage(channelId, messageId);

  if (ownUserId && message) {
    const isMine = message.reactions.some(
      (reaction) => reaction.emoji === emoji && reaction.userId === ownUserId
    );
    const pending = pendingReactions.get(messageId) ?? new Map();

    pending.set(emoji, !isMine);
    pendingReactions.set(messageId, pending);
    storeMessage(
      channelId,
      withOwnReaction(message, emoji, !isMine, ownUserId)
    );
  }

  try {
    const trpc = getTRPCClient();

    await trpc.messages.toggleReaction.mutate({ messageId, emoji });
  } catch (error) {
    pendingReactions.get(messageId)?.delete(emoji);

    if (message) {
      storeMessage(channelId, message);
    }

    throw error;
  }
};

// an update from the server, with any reaction still on its way kept showing
export const updateMessage = (channelId: number, message: TJoinedMessage) => {
  storeMessage(channelId, settlePendingReactions(message));
};

// a message sent from here shows at once under a negative id, faint and with nothing to act on,
// until the server's own copy arrives and takes its place
let nextPendingMessageId = -1;

export const isPendingMessage = (message: TJoinedMessage) => message.id < 0;

export const addPendingMessage = ({
  channelId,
  content,
  clientNonce,
  replyTo,
  parentMessageId
}: {
  channelId: number;
  content: string;
  clientNonce: string;
  replyTo?: TJoinedMessage;
  parentMessageId?: number;
}): number | undefined => {
  const state = store.getState();
  const ownUserId = ownUserIdSelector(state);
  const existing = parentMessageId
    ? threadMessagesMapSelector(state)[parentMessageId]
    : messagesMapSelector(state)[channelId];
  const isDetached =
    !parentMessageId && isChannelDetachedSelector(state, channelId);

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
    clientNonce,
    userId: ownUserId,
    pluginId: null,
    webhookName: null,
    pluginComponents: null,
    channelId,
    parentMessageId: parentMessageId ?? null,
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

  if (parentMessageId) {
    addThreadMessages(parentMessageId, [message]);

    return id;
  }

  store.dispatch(
    serverSliceActions.addMessages({ channelId, messages: [message] })
  );

  return id;
};

export const removePendingMessage = (
  channelId: number,
  messageId: number,
  parentMessageId?: number
) => {
  if (parentMessageId) {
    store.dispatch(
      serverSliceActions.deleteThreadMessage({ parentMessageId, messageId })
    );

    return;
  }

  store.dispatch(serverSliceActions.deleteMessage({ channelId, messageId }));
};

const getPendingSiblings = (channelId: number, parentMessageId?: number) => {
  const state = store.getState();

  if (parentMessageId) {
    return threadMessagesMapSelector(state)[parentMessageId] ?? [];
  }

  return messagesByChannelIdSelector(state, channelId);
};

const PENDING_RELOAD_DELAY_MS = 10_000;

// the server saved it but the live copy never came, lost as the socket dropped, which would
// leave the placeholder for good. the newest page settles it
const reloadIfStillPending = async (
  channelId: number,
  pendingId: number,
  parentMessageId?: number
) => {
  const siblings = getPendingSiblings(channelId, parentMessageId);

  if (!siblings.some((message) => message.id === pendingId)) {
    return;
  }

  try {
    const trpc = getTRPCClient();
    const cursor = null;
    const limit = DEFAULT_MESSAGES_LIMIT;

    if (parentMessageId) {
      const { messages: page } = await trpc.messages.getThread.query({
        parentMessageId,
        cursor,
        limit
      });

      addThreadMessages(parentMessageId, page);
    } else if (!isChannelDetachedSelector(store.getState(), channelId)) {
      // a window of older messages has no place for the newest page
      const { messages: page } = await trpc.messages.get.query({
        channelId,
        cursor,
        limit
      });

      addMessages(channelId, [...page].reverse());
    }
  } catch {
    // no client during a reconnect, which fetches the channel again by itself
  }

  removePendingMessage(channelId, pendingId, parentMessageId);
};

// the server said which message it saved: if it has already arrived, the placeholder goes now,
// otherwise its arrival takes the place of one
export const settlePendingMessage = (
  channelId: number,
  pendingId: number,
  messageId: number | null,
  parentMessageId?: number
) => {
  const messages = getPendingSiblings(channelId, parentMessageId);
  const pending = messages.find((message) => message.id === pendingId);

  if (!pending) {
    return;
  }

  const hasArrived = messages.some((message) => message.id === messageId);

  if (messageId === null || hasArrived) {
    removePendingMessage(channelId, pendingId, parentMessageId);

    return;
  }

  setTimeout(
    () => reloadIfStillPending(channelId, pendingId, parentMessageId),
    PENDING_RELOAD_DELAY_MS
  );
};

// your own message arriving live replaces its placeholder, matched by the nonce it was sent
// with. a copy without one, from a server or an app older than the nonce, takes the oldest
const replacePendingMessage = (channelId: number, message: TJoinedMessage) => {
  const state = store.getState();
  const ownUserId = ownUserIdSelector(state);

  if (message.userId !== ownUserId) {
    return;
  }

  const parentMessageId = message.parentMessageId ?? undefined;
  const messages = getPendingSiblings(channelId, parentMessageId);

  if (messages.some((existing) => existing.id === message.id)) {
    return;
  }

  const pending = messages.find(
    (existing) =>
      isPendingMessage(existing) &&
      (!message.clientNonce || existing.clientNonce === message.clientNonce)
  );

  if (pending) {
    removePendingMessage(channelId, pending.id, parentMessageId);
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
