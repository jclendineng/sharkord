import type { TPinnedCard } from '@/components/channel-view/voice/hooks/use-pin-card-controller';
import { openVoiceChatSidebar } from '@/features/app/actions';
import {
  pushToTalkSelectedSelector,
  voiceChatSidebarDataSelector
} from '@/features/app/selectors';
import { store } from '@/features/store';
import { voiceLogger } from '@/helpers/browser-logger';
import { playSound } from '@/helpers/sounds';
import {
  LocalStorageKey,
  setLocalStorageItem,
  setLocalStorageItemBool
} from '@/helpers/storage';
import { i18n } from '@/i18n';
import { getTRPCClient } from '@/lib/trpc';
import {
  getTrpcError,
  type TExternalStream,
  type TVoiceUserState
} from '@sharkord/shared';
import type { RtpCapabilities } from 'mediasoup-client/types';
import { toast } from 'sonner';
import { setSelectedChannelId } from '../channels/actions';
import {
  currentVoiceChannelIdSelector,
  selectedChannelIdSelector
} from '../channels/selectors';
import { serverSliceActions } from '../slice';
import { SoundType } from '../types';
import { ownUserIdSelector } from '../users/selectors';
import {
  isUserInVoiceSelector,
  isVoiceJoiningSelector,
  ownVoiceStateSelector,
  voiceSessionSelector
} from './selectors';
import { VOICE_REACTION_DURATION_MS } from './statics';

const syncOwnServerMute = (
  userId: number,
  newState: Partial<TVoiceUserState>
): void => {
  const state = store.getState();
  const ownUserId = ownUserIdSelector(state);
  const ownVoiceState = ownVoiceStateSelector(state);

  if (userId !== ownUserId) return;
  if (newState.serverMuted === undefined) return;
  if (newState.serverMuted === ownVoiceState.serverMuted) return;

  if (newState.serverMuted) {
    updateOwnVoiceState({ serverMuted: true, micMuted: true });

    return;
  }

  updateOwnVoiceState({ serverMuted: false });
};

// only a change the server made counts: the user's own toggle already updated their state
const syncOwnStreamsTurnedOff = (
  userId: number,
  previousState: TVoiceUserState | undefined,
  newState: Partial<TVoiceUserState>
): void => {
  const state = store.getState();
  const ownUserId = ownUserIdSelector(state);
  const ownVoiceState = ownVoiceStateSelector(state);

  if (userId !== ownUserId) return;

  if (
    newState.webcamEnabled === false &&
    previousState?.webcamEnabled &&
    ownVoiceState.webcamEnabled
  ) {
    updateOwnVoiceState({ webcamEnabled: false });
  }

  if (
    newState.sharingScreen === false &&
    previousState?.sharingScreen &&
    ownVoiceState.sharingScreen
  ) {
    updateOwnVoiceState({ sharingScreen: false });
  }
};

export const addUserToVoiceChannel = (
  userId: number,
  channelId: number,
  voiceState: TVoiceUserState
): void => {
  const state = store.getState();
  const ownUserId = ownUserIdSelector(state);
  const currentChannelId = currentVoiceChannelIdSelector(state);

  store.dispatch(
    serverSliceActions.addUserToVoiceChannel({
      userId,
      channelId,
      state: voiceState
    })
  );

  syncOwnServerMute(userId, voiceState);

  if (userId !== ownUserId && channelId === currentChannelId) {
    playSound(SoundType.REMOTE_USER_JOINED_VOICE_CHANNEL);
  }
};

const clearLocalVoiceSession = (): void => {
  const state = store.getState();

  const selectedChannelId = selectedChannelIdSelector(state);
  const currentVoiceChannelId = currentVoiceChannelIdSelector(state);

  voiceLogger.info('session: clearing local voice session', {
    selectedChannelId,
    currentVoiceChannelId
  });

  if (selectedChannelId === currentVoiceChannelId) {
    setSelectedChannelId(undefined);
  }

  store.dispatch(serverSliceActions.endVoiceSession());
  updateOwnVoiceState({ webcamEnabled: false, sharingScreen: false });
  setPinnedCard(undefined);
};

export const removeUserFromVoiceChannel = (
  userId: number,
  channelId: number,
  takenOver = false
): void => {
  const state = store.getState();
  const ownUserId = ownUserIdSelector(state);
  const currentChannelId = currentVoiceChannelIdSelector(state);
  const isJoiningVoice = isVoiceJoiningSelector(state);
  const { phase } = voiceSessionSelector(state);

  store.dispatch(
    serverSliceActions.removeUserFromVoiceChannel({ userId, channelId })
  );

  // the device that took the call over hung up, there is nothing left to reconnect from
  if (
    userId === ownUserId &&
    !takenOver &&
    phase === 'takenOver' &&
    !isUserInVoiceSelector(store.getState(), userId)
  ) {
    endVoiceSession();
  }

  if (channelId !== currentChannelId) return;

  // joining while this account sits in voice elsewhere takes that seat over, and the server
  // announces the old seat's leave before the join returns. that leave is ours, but it is not
  // for the call being started
  if (userId === ownUserId && isJoiningVoice) return;

  // the server took us out of this call rather than the other way round: the channel was
  // deleted, its category was, or the runtime was destroyed. without this the call ends but
  // the app goes on showing the user as connected to a channel that no longer exists
  if (userId === ownUserId) {
    voiceLogger.info('session: removed from voice by the server', {
      channelId
    });

    clearLocalVoiceSession();
    playSound(SoundType.OWN_USER_LEFT_VOICE_CHANNEL);

    if (takenOver) {
      store.dispatch(serverSliceActions.setVoiceTakenOver(channelId));
    }

    return;
  }

  playSound(SoundType.REMOTE_USER_LEFT_VOICE_CHANNEL);
};

export const addExternalStreamToVoiceChannel = (
  channelId: number,
  streamId: number,
  stream: TExternalStream
): void => {
  store.dispatch(
    serverSliceActions.addExternalStreamToChannel({
      channelId,
      streamId,
      stream
    })
  );
};

export const updateExternalStreamInVoiceChannel = (
  channelId: number,
  streamId: number,
  stream: TExternalStream
): void => {
  store.dispatch(
    serverSliceActions.updateExternalStreamInChannel({
      channelId,
      streamId,
      stream
    })
  );
};

export const removeExternalStreamFromVoiceChannel = (
  channelId: number,
  streamId: number
): void => {
  store.dispatch(
    serverSliceActions.removeExternalStreamFromChannel({
      channelId,
      streamId
    })
  );
};

export const updateVoiceUserState = (
  userId: number,
  channelId: number,
  newState: Partial<TVoiceUserState>
): void => {
  const state = store.getState();
  const ownUserId = ownUserIdSelector(state);
  const currentChannelId = currentVoiceChannelIdSelector(state);
  const currentUserState = state.server.voiceMap[channelId]?.users[userId];

  if (userId !== ownUserId && channelId === currentChannelId) {
    if (newState.sharingScreen === true && !currentUserState?.sharingScreen) {
      playSound(SoundType.REMOTE_USER_STARTED_SCREENSHARE);
    } else if (
      newState.sharingScreen === false &&
      currentUserState?.sharingScreen
    ) {
      playSound(SoundType.REMOTE_USER_STOPPED_SCREENSHARE);
    }
  }

  store.dispatch(
    serverSliceActions.updateVoiceUserState({ userId, channelId, newState })
  );

  if (channelId === currentChannelId) {
    syncOwnServerMute(userId, newState);
    syncOwnStreamsTurnedOff(userId, currentUserState, newState);
  }
};

let nextVoiceReactionId = 0;

export const showVoiceReaction = (userId: number, emoji: string): void => {
  const id = ++nextVoiceReactionId;

  store.dispatch(
    serverSliceActions.addVoiceReaction({ userId, reaction: { id, emoji } })
  );

  setTimeout(() => {
    store.dispatch(
      serverSliceActions.removeVoiceReaction({ userId, reactionId: id })
    );
  }, VOICE_REACTION_DURATION_MS);
};

export const updateOwnVoiceState = (
  newState: Partial<TVoiceUserState>
): void => {
  store.dispatch(serverSliceActions.updateOwnVoiceState(newState));
};

export const joinVoice = async (
  channelId: number
): Promise<RtpCapabilities | undefined> => {
  const state = store.getState();
  const currentChannelId = currentVoiceChannelIdSelector(state);

  // already in the desired channel, or on the way into one
  if (channelId === currentChannelId || isVoiceJoiningSelector(state)) {
    return undefined;
  }

  const voiceChatSidebar = voiceChatSidebarDataSelector(state);
  const isFollowingVoiceChat =
    voiceChatSidebar.isOpen &&
    voiceChatSidebar.channelId !== undefined &&
    voiceChatSidebar.channelId === currentChannelId;

  // is already in a voice channel, leave it first. its local part runs before its first await,
  // so the join is marked with no gap for a second click to get in
  const leaving = currentChannelId
    ? leaveVoice({ reason: 'switch_channel' })
    : undefined;

  store.dispatch(serverSliceActions.startVoiceJoin(channelId));

  await leaving;

  // an open chat of the call being left moves to the new call's chat. it is never opened on
  // its own, joining a call leaves a closed chat closed
  if (isFollowingVoiceChat) {
    openVoiceChatSidebar(channelId);
  }

  const { micMuted: storedMicMuted, soundMuted } = ownVoiceStateSelector(state);
  const pushToTalkSelected = pushToTalkSelectedSelector(state);

  const micMuted = storedMicMuted || pushToTalkSelected;

  if (micMuted !== storedMicMuted) {
    updateOwnVoiceState({ micMuted });
  }

  voiceLogger.info('session: join requested', {
    channelId,
    micMuted,
    soundMuted
  });

  try {
    const client = getTRPCClient();

    const { routerRtpCapabilities } = await client.voice.join.mutate({
      channelId,
      state: { micMuted, soundMuted }
    });

    voiceLogger.info('session: joined', { channelId });

    store.dispatch(serverSliceActions.setVoiceConnecting(channelId));

    return routerRtpCapabilities;
  } catch (error) {
    voiceLogger.error('session: join failed', error, { channelId });
    clearLocalVoiceSession();

    toast.error(getTrpcError(error, i18n.t('common:failedJoinVoiceChannel')));
  }

  return undefined;
};

export type TLeaveVoiceReason =
  'user_disconnect_button' | 'switch_channel' | 'init_failed' | 'unknown';

export const leaveVoice = async (options?: {
  reason?: TLeaveVoiceReason;
}): Promise<void> => {
  const state = store.getState();
  const currentChannelId = currentVoiceChannelIdSelector(state);
  const selectedChannelId = selectedChannelIdSelector(state);
  const reason = options?.reason ?? 'unknown';

  if (!currentChannelId) {
    voiceLogger.info('session: leave requested with no active channel', {
      reason
    });
    return;
  }

  voiceLogger.info('session: leave requested', {
    reason,
    channelId: currentChannelId,
    selectedChannelId
  });

  clearLocalVoiceSession();

  try {
    const client = getTRPCClient();

    await client.voice.leave.mutate();
    playSound(SoundType.OWN_USER_LEFT_VOICE_CHANNEL);
  } catch (error) {
    voiceLogger.error('session: leave failed', error, {
      channelId: currentChannelId
    });
    toast.error(getTrpcError(error, i18n.t('common:failedLeaveVoiceChannel')));
  }
};

export const setVoiceInCall = (channelId: number): void => {
  store.dispatch(serverSliceActions.setVoiceInCall(channelId));
};

// the server ends the call of a socket that closes, so the call stops with the connection, as
// it does in the apps, and is joined again once the connection is back
export const holdVoiceForRejoin = (): void => {
  const currentVoiceChannelId = currentVoiceChannelIdSelector(store.getState());

  if (currentVoiceChannelId === undefined) return;

  voiceLogger.info('session: call ended by a dropped connection', {
    channelId: currentVoiceChannelId
  });

  playSound(SoundType.OWN_USER_LEFT_VOICE_CHANNEL);
  store.dispatch(serverSliceActions.awaitVoiceRejoin(currentVoiceChannelId));
  updateOwnVoiceState({ webcamEnabled: false, sharingScreen: false });
  setPinnedCard(undefined);
};

// the voice provider that does the joining is React's, so the join is picked up from here by
// useFollowVoiceMove
export const rejoinVoiceAfterReconnect = (): void => {
  const session = voiceSessionSelector(store.getState());

  if (session.phase !== 'awaitingRejoin') return;

  store.dispatch(serverSliceActions.setVoiceRejoinReady(session.channelId));
};

export const endVoiceSession = (): void => {
  store.dispatch(serverSliceActions.endVoiceSession());
};

export const setVoiceMoveTargetChannelId = (
  channelId: number | undefined
): void => {
  store.dispatch(serverSliceActions.setVoiceMoveTargetChannelId(channelId));
};

export const setPinnedCard = (pinnedCard: TPinnedCard | undefined): void => {
  store.dispatch(serverSliceActions.setPinnedCard(pinnedCard));
};

export const setHideNonVideoParticipants = (value: boolean): void => {
  store.dispatch(serverSliceActions.setHideNonVideoParticipants(value));

  try {
    setLocalStorageItem(
      LocalStorageKey.HIDE_NON_VIDEO_PARTICIPANTS,
      String(value)
    );
  } catch (error) {
    console.error('Failed to save voice options:', error);
  }
};

export const setIncomingVideoOff = (value: boolean): void => {
  store.dispatch(serverSliceActions.setIncomingVideoOff(value));

  try {
    setLocalStorageItemBool(LocalStorageKey.INCOMING_VIDEO_OFF, value);
  } catch (error) {
    console.error('Failed to save voice options:', error);
  }
};

export const setShowUserBannersInVoice = (value: boolean): void => {
  store.dispatch(serverSliceActions.setShowUserBannersInVoice(value));

  try {
    setLocalStorageItemBool(
      LocalStorageKey.VOICE_CHAT_SHOW_USER_BANNERS,
      value
    );
  } catch (error) {
    console.error('Failed to save voice options:', error);
  }
};

export const setHideOwnScreenShare = (value: boolean): void => {
  store.dispatch(serverSliceActions.setHideOwnScreenShare(value));

  try {
    setLocalStorageItemBool(LocalStorageKey.HIDE_OWN_SCREEN_SHARE, value);
  } catch (error) {
    console.error('Failed to save voice options:', error);
  }
};

export const setAlwaysShowVoiceControls = (value: boolean): void => {
  store.dispatch(serverSliceActions.setAlwaysShowVoiceControls(value));

  try {
    setLocalStorageItemBool(LocalStorageKey.ALWAYS_SHOW_VOICE_CONTROLS, value);
  } catch (error) {
    console.error('Failed to save voice options:', error);
  }
};
