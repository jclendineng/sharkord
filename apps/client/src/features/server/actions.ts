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
  infoSelector,
  serverSnapshotSelector,
  snapshotChannelIdSelector
} from './selectors';
import { serverSliceActions } from './slice';
import { SoundType, type TDisconnectInfo, type TServerSnapshot } from './types';
import { rejoinVoiceAfterReconnect } from './voice/actions';

let unsubscribeFromServer: (() => void) | null = null;

export const setConnected = (status: boolean) => {
  store.dispatch(serverSliceActions.setConnected(status));
};

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

export const connect = async () => {
  const state = store.getState();
  const info = infoSelector(state);

  if (!info) {
    throw new Error('Failed to fetch server info');
  }

  const { serverId } = info;

  const host = getHostFromServer();
  const trpc = await connectToTRPC(host);

  const { hasPassword, handshakeHash } = await trpc.others.handshake.query();

  if (hasPassword) {
    // show password prompt
    openDialog(Dialog.SERVER_PASSWORD, { handshakeHash, serverId });
    return;
  }

  const { showWelcomeDialog } = await joinServer(handshakeHash);

  if (showWelcomeDialog) {
    openDialog(Dialog.WELCOME_PROFILE_SETUP);
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

// the restored copy of a channel may hold messages deleted since, so its first fetched page
// replaces it rather than merging in. true once, for that channel
export const takeSnapshotChannel = (channelId: number): boolean => {
  const snapshotChannelId = snapshotChannelIdSelector(store.getState());

  if (snapshotChannelId !== channelId) return false;

  store.dispatch(serverSliceActions.clearSnapshotChannel());

  return true;
};

export const disconnectFromServer = () => {
  cleanup();
  unsubscribeFromServer?.();
};

const RECONNECT_DELAYS_MS = [1_000, 2_000, 4_000, 8_000, 8_000];

let reconnectAttempt = 0;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let reconnectDisconnectInfo: TDisconnectInfo | undefined;

export const cancelReconnect = () => {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }

  reconnectAttempt = 0;
  reconnectDisconnectInfo = undefined;
};

const abandonReconnect = () => {
  const info = reconnectDisconnectInfo;

  cleanup();
  setDisconnectInfo(info);
  playSound(SoundType.SERVER_DISCONNECTED);
};

// a reconnected socket starts unauthenticated: the server only sets ctx.authenticated and
// tracks the user in joinServer, and every subscription sits behind that. so recovering a
// dropped connection means replaying the whole join, not just reopening the transport.
export const reconnectToServer = (info: TDisconnectInfo) => {
  if (reconnectTimer) return;

  const state = store.getState();

  if (reconnectAttempt === 0 && !connectedSelector(state)) {
    setConnected(false);
    cleanup();

    return;
  }

  setConnected(false);

  reconnectDisconnectInfo = info;

  const delay = RECONNECT_DELAYS_MS[reconnectAttempt];

  if (delay === undefined) {
    abandonReconnect();
    return;
  }

  reconnectAttempt += 1;

  pushVoiceDebugEvent('ws', 'reconnect scheduled', {
    attempt: reconnectAttempt,
    delay,
    code: info.code,
    reason: info.reason
  });

  store.dispatch(
    serverSliceActions.setReconnect({
      attempt: reconnectAttempt,
      maxAttempts: RECONNECT_DELAYS_MS.length,
      nextAttemptAt: Date.now() + delay
    })
  );

  reconnectTimer = setTimeout(async () => {
    reconnectTimer = null;

    store.dispatch(
      serverSliceActions.setReconnect({
        attempt: reconnectAttempt,
        maxAttempts: RECONNECT_DELAYS_MS.length,
        nextAttemptAt: null
      })
    );

    try {
      // connect() opens the password dialog instead of joining when the server asks for one,
      // so reconnecting stays true until setInitialData clears it
      await connect();
      cancelReconnect();
      rejoinVoiceAfterReconnect();

      pushVoiceDebugEvent('ws', 'reconnected', {
        voiceChannelId: currentVoiceChannelIdSelector(store.getState())
      });
    } catch (error) {
      logDebug('reconnect attempt failed', error);

      pushVoiceDebugEvent('error', 'reconnect attempt failed', {
        error: String(error)
      });

      const isAuthFailure =
        error instanceof TRPCClientError &&
        (error.data?.code === 'UNAUTHORIZED' ||
          error.data?.code === 'FORBIDDEN');

      if (isAuthFailure) {
        abandonReconnect();
        return;
      }

      reconnectToServer(info);
    }
  }, delay);
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
