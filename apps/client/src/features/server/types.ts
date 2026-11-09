import {
  type TCategory,
  type TChannel,
  type TChannelUserPermissionsMap,
  type TExternalStreamsMap,
  type TJoinedEmoji,
  type TJoinedMessage,
  type TJoinedPublicUser,
  type TJoinedRole,
  type TJoinedSoundboardSound,
  type TJoinedSticker,
  type TPluginMetadata,
  type TPublicServerSettings,
  type TReadStateMap,
  type TVoiceMap,
  type TVoiceUserState
} from '@sharkord/shared';

// what joining the server fills the store with
export type TInitialData = {
  serverId: string;
  categories: TCategory[];
  channels: TChannel[];
  users: TJoinedPublicUser[];
  ownUserId: number;
  ownUserPasswordSet: boolean;
  roles: TJoinedRole[];
  emojis: TJoinedEmoji[];
  stickers?: TJoinedSticker[];
  sounds?: TJoinedSoundboardSound[];
  publicSettings: TPublicServerSettings | undefined;
  voiceMap: TVoiceMap;
  externalStreamsMap: TExternalStreamsMap;
  channelPermissions: TChannelUserPermissionsMap;
  readStates: TReadStateMap;
  pluginsMetadata: TPluginMetadata[];
};

// the copy of the server a refresh shows until joining again returns, with the open channel's
// latest messages
export type TServerSnapshot = TInitialData & {
  selectedChannelId: number | undefined;
  messages: TJoinedMessage[];
};

export enum SoundType {
  MESSAGE_RECEIVED = 'message_received',
  MESSAGE_SENT = 'message_sent',
  SERVER_DISCONNECTED = 'server_disconnected',

  OWN_USER_LEFT_VOICE_CHANNEL = 'own_user_left_voice_channel',
  OWN_USER_JOINED_VOICE_CHANNEL = 'own_user_joined_voice_channel',
  OWN_USER_MUTED_MIC = 'own_user_muted_mic',
  OWN_USER_UNMUTED_MIC = 'own_user_unmuted_mic',
  OWN_USER_MUTED_SOUND = 'own_user_muted_sound',
  OWN_USER_UNMUTED_SOUND = 'own_user_unmuted_sound',
  OWN_USER_STARTED_WEBCAM = 'own_user_started_webcam',
  OWN_USER_STOPPED_WEBCAM = 'own_user_stopped_webcam',
  OWN_USER_STARTED_SCREENSHARE = 'own_user_started_screenshare',
  OWN_USER_STOPPED_SCREENSHARE = 'own_user_stopped_screenshare',

  REMOTE_USER_JOINED_VOICE_CHANNEL = 'remote_user_joined_voice_channel',
  REMOTE_USER_LEFT_VOICE_CHANNEL = 'remote_user_left_voice_channel',
  REMOTE_USER_STARTED_SCREENSHARE = 'remote_user_started_screenshare',
  REMOTE_USER_STOPPED_SCREENSHARE = 'remote_user_stopped_screenshare'
}

export type TMessagesMap = {
  [channelId: number]: TJoinedMessage[];
};

export type TThreadMessagesMap = {
  [parentMessageId: number]: TJoinedMessage[];
};

export type TDisconnectInfo = {
  code: number;
  reason: string;
  wasClean: boolean;
  time: Date;
};

export type TVoiceUser = TJoinedPublicUser & {
  state: TVoiceUserState;
};

export type TVoiceReaction = {
  id: number;
  emoji: string;
};

// where this tab's connection to the server stands, the same states as the apps' Phase. a page
// restored from its snapshot shows the server inert while joining runs
export type TConnectionState =
  | { kind: 'signedOut'; disconnectInfo?: TDisconnectInfo }
  | { kind: 'connecting'; auto: boolean }
  | { kind: 'restoring' }
  | {
      kind: 'needsServerPassword';
      resumesFrom: 'signIn' | 'reconnect' | 'restore';
    }
  | { kind: 'connected' }
  | {
      kind: 'reconnecting';
      attempt: number;
      nextAttemptAt: number | null;
    };

export type TVoiceSession =
  | { phase: 'idle' }
  | { phase: 'joining' | 'connecting' | 'inCall'; channelId: number }
  // the connection dropped and took the call with it, joined again once it is back
  | { phase: 'awaitingRejoin' | 'rejoinReady'; channelId: number }
  // this account joined from another device, which took the seat. a banner offers it back
  | { phase: 'takenOver'; channelId: number };
