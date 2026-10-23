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
import {
  setCurrentVoiceChannelId,
  setSelectedChannelId
} from '../channels/actions';
import {
  currentVoiceChannelIdSelector,
  selectedChannelIdSelector
} from '../channels/selectors';
import { ownVoiceUserSelector } from '../selectors';
import { serverSliceActions } from '../slice';
import { SoundType } from '../types';
import { ownUserIdSelector } from '../users/selectors';
import { ownVoiceStateSelector } from './selectors';
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

  setCurrentVoiceChannelId(undefined);
  updateOwnVoiceState({ webcamEnabled: false, sharingScreen: false });
  setPinnedCard(undefined);
};

// joining while this account sits in voice elsewhere takes that seat over, and the server
// announces the old seat's leave before the join returns. that leave is ours, but it is not
// for the call being started
let isJoiningVoice = false;

export const removeUserFromVoiceChannel = (
  userId: number,
  channelId: number
): void => {
  const state = store.getState();
  const ownUserId = ownUserIdSelector(state);
  const currentChannelId = currentVoiceChannelIdSelector(state);

  store.dispatch(
    serverSliceActions.removeUserFromVoiceChannel({ userId, channelId })
  );

  if (channelId !== currentChannelId) return;

  if (userId === ownUserId && isJoiningVoice) return;

  // the server took us out of this call rather than the other way round: the channel was
  // deleted, its category was, or the runtime was destroyed. without this the call ends but
  // the app goes on showing the user as connected to a channel that no longer exists
  if (userId === ownUserId) {
    voiceLogger.info('session: removed from voice by the server', {
      channelId
    });

    clearLocalVoiceSession();

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

  if (channelId === currentChannelId) {
    // already in the desired channel
    return undefined;
  }

  const voiceChatSidebar = voiceChatSidebarDataSelector(state);
  const isFollowingVoiceChat =
    voiceChatSidebar.isOpen &&
    voiceChatSidebar.channelId !== undefined &&
    voiceChatSidebar.channelId === currentChannelId;

  if (currentChannelId) {
    // is already in a voice channel, leave it first
    await leaveVoice({ reason: 'switch_channel' });
  }

  setCurrentVoiceChannelId(channelId);

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

  isJoiningVoice = true;

  try {
    const client = getTRPCClient();

    const { routerRtpCapabilities } = await client.voice.join.mutate({
      channelId,
      state: { micMuted, soundMuted }
    });

    voiceLogger.info('session: joined', { channelId });

    return routerRtpCapabilities;
  } catch (error) {
    voiceLogger.error('session: join failed', error, { channelId });
    clearLocalVoiceSession();

    toast.error(getTrpcError(error, i18n.t('common:failedJoinVoiceChannel')));
  } finally {
    isJoiningVoice = false;
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

// the server ends the call of a socket that closes, so a connection that dropped mid call comes
// back with the call gone while this client still shows it. the stale session is released and
// the call joined again, the way a move is
export const rejoinVoiceAfterReconnect = (): void => {
  const state = store.getState();
  const currentVoiceChannelId = currentVoiceChannelIdSelector(state);
  const ownVoiceUser = ownVoiceUserSelector(state);

  if (currentVoiceChannelId === undefined || ownVoiceUser) return;

  voiceLogger.info('session: call ended by the reconnect, joining again', {
    channelId: currentVoiceChannelId
  });

  clearLocalVoiceSession();
  setVoiceMoveTargetChannelId(currentVoiceChannelId);
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
