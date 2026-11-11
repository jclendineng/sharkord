import { Dialog } from '@/components/dialogs/dialogs';
import { logDebug } from '@/helpers/browser-logger';
import { getHostFromServer } from '@/helpers/get-file-url';
import { playSound } from '@/helpers/sounds';
import {
  getSessionStorageItem,
  removeSessionStorageItem,
  SessionStorageKey,
  setSessionStorageItem
} from '@/helpers/storage';
import { pushVoiceDebugEvent } from '@/helpers/voice-debug';
import { i18n } from '@/i18n';
import { cleanup, connectToTRPC, getTRPCClient } from '@/lib/trpc';
import type { TMessageJumpToTarget } from '@/types';
import {
  DisconnectCode,
  type TLocale,
  type TPublicServerSettings,
  type TServerInfo
} from '@sharkord/shared';
import { TRPCClientError } from '@trpc/client';
import { toast } from 'sonner';
import { appSliceActions } from '../app/slice';
import { openDialog } from '../dialogs/actions';
import { store } from '../store';
import {
  channelReadStateByIdSelector,
  currentVoiceChannelIdSelector,
  isChannelTextVisibleByIdSelector
} from './channels/selectors';
import {
  processPluginComponents,
  setPluginCapabilityAccess,
  setPluginCommands,
  setPluginComponents
} from './plugins/actions';
import {
  connectedSelector,
  connectionSelector,
  infoSelector,
  isChannelStaleSelector,
  serverSnapshotSelector
} from './selectors';
import { serverSliceActions } from './slice';
import { SoundType, type TDisconnectInfo, type TServerSnapshot } from './types';
import { holdVoiceForRejoin, rejoinVoiceAfterReconnect } from './voice/actions';

let unsubscribeFromServer: (() => void) | null = null;

export const resetServerState = () => {
  store.dispatch(serverSliceActions.resetState());
};

export const setDisconnectInfo = (info: TDisconnectInfo | undefined) => {
  store.dispatch(serverSliceActions.setDisconnectInfo(info));
};

export const setDmsOpen = (open: boolean) => {
  store.dispatch(serverSliceActions.setDmsOpen(open));
};

export const setPublicServerSettings = (
  settings: TPublicServerSettings | undefined
) => {
  store.dispatch(serverSliceActions.setPublicSettings(settings));
};

export const setInfo = (info: TServerInfo | undefined) => {
  store.dispatch(serverSliceActions.setInfo(info));
};

export const setActiveFullscreenPluginId = (pluginId: string | undefined) => {
  store.dispatch(serverSliceActions.setActiveFullscreenPluginId(pluginId));
};

export const finishConnecting = () => {
  if (connectionSelector(store.getState()).kind === 'connecting') {
    store.dispatch(serverSliceActions.setDisconnectInfo(undefined));
  }
};

export const connect = async (options?: { auto?: boolean }) => {
  store.dispatch(serverSliceActions.setConnecting(!!options?.auto));

  try {
    const state = store.getState();
    const info = infoSelector(state);

    if (!info) {
      throw new Error('Failed to fetch server info');
    }

    const host = getHostFromServer();
    const trpc = await connectToTRPC(host);

    const { hasPassword, handshakeHash } = await trpc.others.handshake.query();

    if (hasPassword) {
      store.dispatch(serverSliceActions.setNeedsServerPassword());
      // show password prompt
      openDialog(Dialog.SERVER_PASSWORD, { handshakeHash });
      return;
    }

    const { showWelcomeDialog } = await joinServer(handshakeHash);

    if (showWelcomeDialog) {
      openDialog(Dialog.WELCOME_PROFILE_SETUP);
    }
  } catch (error) {
    // an automatic one is finished by its caller, whose clean up of the saved login has to
    // land before the connect screen shows
    if (!options?.auto) {
      finishConnecting();
    }

    throw error;
  }
};

export const joinServer = async (handshakeHash: string, password?: string) => {
  const trpc = getTRPCClient();
  const data = await trpc.others.joinServer.query({
    handshakeHash,
    password,
    locale: i18n.resolvedLanguage as TLocale
  });

  logDebug('joinServer', data);

  const { initSubscriptions } = await import('./subscriptions');

  try {
    unsubscribeFromServer?.();
  } catch (error) {
    logDebug('failed to unsubscribe stale subscriptions', error);
  }

  unsubscribeFromServer = initSubscriptions();

  store.dispatch(serverSliceActions.setInitialData(data));

  // here rather than after connect(), which returns as soon as a server password is asked for,
  // with the voice map still the one from before the socket dropped
  rejoinVoiceAfterReconnect();

  setPluginCommands(data.commands);
  setPluginCapabilityAccess(data.pluginCapabilityAccess);

  const components = await processPluginComponents(
    data.pluginIdsWithComponents
  );

  setPluginComponents(components);

  return {
    showWelcomeDialog: data.showWelcomeDialog
  };
};

// a copy too big for the tab's storage is not kept, the page then loads as before
const MAX_SNAPSHOT_LENGTH = 2_000_000;

// kept in the tab's session storage, so it outlives a refresh but not the tab, and is dropped
// with the session on signing out
export const saveServerSnapshot = () => {
  const state = store.getState();

  if (!connectedSelector(state)) return;

  const snapshot = serverSnapshotSelector(state);

  if (!snapshot) return;

  const serialized = JSON.stringify(snapshot);

  if (serialized.length > MAX_SNAPSHOT_LENGTH) return;

  setSessionStorageItem(SessionStorageKey.SERVER_SNAPSHOT, serialized);
};

export const clearServerSnapshot = () => {
  removeSessionStorageItem(SessionStorageKey.SERVER_SNAPSHOT);
};

// whether a copy of this server was there to show while joining runs
export const restoreServerSnapshot = (): boolean => {
  const serialized = getSessionStorageItem(SessionStorageKey.SERVER_SNAPSHOT);
  const info = infoSelector(store.getState());

  if (!serialized || !info) return false;

  try {
    const snapshot: TServerSnapshot = JSON.parse(serialized);

    if (snapshot.serverId !== info.serverId) return false;

    store.dispatch(serverSliceActions.restoreSnapshot(snapshot));

    return true;
  } catch {
    clearServerSnapshot();

    return false;
  }
};

// a stale channel (restored after a refresh, or loaded before a reconnect) may hold messages
// deleted since and miss ones sent since, so its first fetched page replaces it rather than
// merging in. true once, for that channel
export const takeStaleChannel = (channelId: number): boolean => {
  if (!isChannelStaleSelector(store.getState(), channelId)) return false;

  store.dispatch(serverSliceActions.clearStaleChannel(channelId));

  return true;
};

export const disconnectFromServer = () => {
  cleanup();
  unsubscribeFromServer?.();
};

const MAX_RECONNECT_DELAY_MS = 30_000;

// the first retry is immediate, a dropped socket usually comes straight back, only repeated
// failures back off. the same schedule as the apps'
const getReconnectDelay = (attempt: number) =>
  attempt === 1
    ? 0
    : Math.min(1_000 * 2 ** (attempt - 2), MAX_RECONNECT_DELAY_MS);

let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let runWaitingReconnect: (() => Promise<void>) | null = null;

export const cancelReconnect = () => {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
};

const abandonReconnect = (info: TDisconnectInfo) => {
  cleanup();
  setDisconnectInfo(info);
  playSound(SoundType.SERVER_DISCONNECTED);
};

// the server turned the session down, rather than a rate limit or a connection that dropped,
// which leave the session good for the next try
export const isAuthFailure = (error: unknown) => {
  if (!(error instanceof TRPCClientError)) return false;

  const { data, cause } = error;

  if (data?.code === 'UNAUTHORIZED' || data?.code === 'FORBIDDEN') return true;

  // a token refused while the socket opens arrives as the close, see createContext on the server
  return (
    cause instanceof CloseEvent && cause.code === DisconnectCode.UNAUTHORIZED
  );
};

// a reconnected socket starts unauthenticated: the server only sets ctx.authenticated and
// tracks the user in joinServer, and every subscription sits behind that. so recovering a
// dropped connection means replaying the whole join, not just reopening the transport.
export const reconnectToServer = (info: TDisconnectInfo) => {
  if (reconnectTimer) return;

  const connection = connectionSelector(store.getState());

  // a socket that never finished joining has nothing to go back to
  if (connection.kind !== 'connected' && connection.kind !== 'reconnecting') {
    cleanup();

    return;
  }

  if (connection.kind === 'connected') {
    holdVoiceForRejoin();
  }

  store.dispatch(serverSliceActions.markLoadedChannelsStale());

  const attempt =
    connection.kind === 'reconnecting' ? connection.attempt + 1 : 1;
  const delay = getReconnectDelay(attempt);

  pushVoiceDebugEvent('ws', 'reconnect scheduled', {
    attempt,
    delay,
    code: info.code,
    reason: info.reason
  });

  store.dispatch(
    serverSliceActions.setReconnect({
      attempt,
      nextAttemptAt: Date.now() + delay
    })
  );

  runWaitingReconnect = async () => {
    reconnectTimer = null;
    runWaitingReconnect = null;

    store.dispatch(
      serverSliceActions.setReconnect({ attempt, nextAttemptAt: null })
    );

    try {
      await connect();
      cancelReconnect();

      pushVoiceDebugEvent('ws', 'reconnected', {
        voiceChannelId: currentVoiceChannelIdSelector(store.getState())
      });
    } catch (error) {
      logDebug('reconnect attempt failed', error);

      pushVoiceDebugEvent('error', 'reconnect attempt failed', {
        error: String(error)
      });

      if (isAuthFailure(error)) {
        abandonReconnect(info);
        return;
      }

      reconnectToServer(info);
    }
  };

  reconnectTimer = setTimeout(runWaitingReconnect, delay);
};

// back in the foreground or back online is the moment to try without waiting out the delay,
// as the apps do when they become active
export const retryReconnectNow = () => {
  if (!reconnectTimer || !runWaitingReconnect) return;

  clearTimeout(reconnectTimer);
  runWaitingReconnect();
};

export const jumpToMessage = (target: TMessageJumpToTarget) => {
  store.dispatch(appSliceActions.setMessageJumpTarget(target));

  if (target.isDm) {
    setDmsOpen(true);
    store.dispatch(appSliceActions.setSelectedDmChannelId(target.channelId));

    return;
  }

  setDmsOpen(false);
  store.dispatch(appSliceActions.setSelectedDmChannelId(undefined));
  store.dispatch(serverSliceActions.setSelectedChannelId(target.channelId));

  const state = store.getState();

  if (isChannelTextVisibleByIdSelector(state, target.channelId)) {
    markChannelAsRead(target.channelId);
  }
};

export const markChannelAsRead = async (
  channelId: number,
  force: boolean = false
) => {
  const state = store.getState();
  const unreadCount = channelReadStateByIdSelector(state, channelId);

  if (!force && unreadCount === 0) {
    return;
  }

  if (unreadCount > 0) {
    store.dispatch(
      serverSliceActions.setChannelReadState({ channelId, count: 0 })
    );
  }

  try {
    const trpc = getTRPCClient();

    await trpc.channels.markAsRead.mutate({ channelId });
  } catch {
    if (unreadCount > 0) {
      store.dispatch(
        serverSliceActions.setChannelReadState({
          channelId,
          count: unreadCount
        })
      );
    }
  }
};

window.useToken = async (token: string) => {
  const trpc = getTRPCClient();

  try {
    await trpc.others.useSecretToken.mutate({ token });

    toast.success(i18n.t('common:nowServerOwner'));
  } catch {
    toast.error(i18n.t('common:invalidAccessToken'));
  }
};

window.sharkordDebug = {
  ...window.sharkordDebug,
  openSoundsModal: () => openDialog(Dialog.SOUNDS)
};
