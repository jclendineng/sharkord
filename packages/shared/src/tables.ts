import type { InferInsertModel, InferSelectModel } from 'drizzle-orm';
import {
  activityLog,
  categories,
  channelReadStates,
  channelRolePermissions,
  channels,
  channelUserPermissions,
  directMessages,
  emojis,
  files,
  invites,
  logins,
  messageFiles,
  messageReactions,
  messages,
  pollAnswers,
  polls,
  rolePermissions,
  roles,
  settings,
  soundboardSounds,
  stickers,
  userRoles,
  users
} from '../../../apps/server/src/db/schema';
import type { Permission } from './statics';
import type { UserStatus } from './types';

export type TSettings = InferSelectModel<typeof settings>;
export type TRole = InferSelectModel<typeof roles>;
export type TCategory = InferSelectModel<typeof categories>;
export type TChannel = InferSelectModel<typeof channels>;
export type TFile = InferSelectModel<typeof files> & {
  _accessToken?: string;
  _accessTokenExpiresAt?: number;
};
export type TUser = InferSelectModel<typeof users>;
export type TLogin = InferSelectModel<typeof logins>;
export type TMessage = InferSelectModel<typeof messages>;
export type TMessageFile = InferSelectModel<typeof messageFiles>;
export type TRolePermission = InferSelectModel<typeof rolePermissions>;
export type TEmoji = InferSelectModel<typeof emojis>;
export type TMessageReaction = InferSelectModel<typeof messageReactions>;
export type TInvite = InferSelectModel<typeof invites>;
export type TActivityLog = InferSelectModel<typeof activityLog>;
export type TUserRole = InferSelectModel<typeof userRoles>;
export type TChannelRolePermission = InferSelectModel<
  typeof channelRolePermissions
>;
export type TChannelUserPermission = InferSelectModel<
  typeof channelUserPermissions
>;
export type TChannelReadState = InferSelectModel<typeof channelReadStates>;
export type TDirectMessage = InferSelectModel<typeof directMessages>;

export type TISettings = InferInsertModel<typeof settings>;
export type TIRole = InferInsertModel<typeof roles>;
export type TICategory = InferInsertModel<typeof categories>;
export type TIChannel = InferInsertModel<typeof channels>;
export type TIFile = InferInsertModel<typeof files>;
export type TIUser = InferInsertModel<typeof users>;
export type TILogin = InferInsertModel<typeof logins>;
export type TIMessage = InferInsertModel<typeof messages>;
export type TIMessageFile = InferInsertModel<typeof messageFiles>;
export type TIRolePermission = InferInsertModel<typeof rolePermissions>;
export type TIEmoji = InferInsertModel<typeof emojis>;
export type TIMessageReaction = InferInsertModel<typeof messageReactions>;
export type TIInvite = InferInsertModel<typeof invites>;
export type TIActivityLog = InferInsertModel<typeof activityLog>;
export type TIUserRole = InferInsertModel<typeof userRoles>;
export type TIChannelRolePermission = InferInsertModel<
  typeof channelRolePermissions
>;
export type TIChannelUserPermission = InferInsertModel<
  typeof channelUserPermissions
>;
export type TIChannelReadState = InferInsertModel<typeof channelReadStates>;
export type TIDirectMessage = InferInsertModel<typeof directMessages>;

export type TStorageSettings = Pick<
  TSettings,
  | 'storageUploadEnabled'
  | 'storageFileSharingInDirectMessages'
  | 'storageQuota'
  | 'storageUploadMaxFileSize'
  | 'storageMaxAvatarSize'
  | 'storageMaxBannerSize'
  | 'storageMaxFilesPerMessage'
  | 'storageSpaceQuotaByUser'
  | 'storageOverflowAction'
  | 'storageSignedUrlsTtlSeconds'
  | 'storageImageOptimizationEnabled'
  | 'storageImageOptimizationQuality'
>;

// joined types

type TPublicUser = Pick<
  TJoinedUser,
  | 'id'
  | 'name'
  | 'profileColor'
  | 'bio'
  | 'avatar'
  | 'avatarId'
  | 'banner'
  | 'bannerId'
  | 'banned'
  | 'createdAt'
> & {
  status?: UserStatus;
  // only where the profile is loaded in full, a creator embedded in an invite leaves it out
  customStatus?: string | null;
  _identity?: string;
};

export type TJoinedRole = TRole & {
  permissions: Permission[];
};

export type TJoinedMessageReaction = TMessageReaction & {
  file: TFile | null;
};

export type TMessageReplyPreview = Pick<
  TMessage,
  'id' | 'content' | 'userId' | 'pluginId'
>;

export type TSticker = InferSelectModel<typeof stickers>;

export type TJoinedSticker = TSticker & {
  file: TFile;
};

export type TSoundboardSound = InferSelectModel<typeof soundboardSounds>;

export type TJoinedSoundboardSound = TSoundboardSound & {
  file: TFile;
};

export type TPoll = InferSelectModel<typeof polls>;
export type TPollAnswer = InferSelectModel<typeof pollAnswers>;

export type TJoinedPollAnswer = Pick<TPollAnswer, 'id' | 'text' | 'emoji'> & {
  userIds: number[];
};

export type TJoinedPoll = Pick<
  TPoll,
  'question' | 'allowMultiple' | 'expiresAt' | 'endedAt'
> & {
  answers: TJoinedPollAnswer[];
};

export type TJoinedMessage = TMessage & {
  files: TFile[];
  reactions: TJoinedMessageReaction[];
  poll: TJoinedPoll | null;
  sticker: TJoinedSticker | null;
  replyCount?: number;
  replyTo?: TMessageReplyPreview | null;
};

export type TJoinedEmoji = TEmoji & {
  file: TFile;
  user: TPublicUser;
};

export type TJoinedUser = TUser & {
  avatar: TFile | null;
  banner: TFile | null;
  roleIds: number[];
};

export type TJoinedPublicUser = TPublicUser & {
  avatar: TFile | null;
  banner: TFile | null;
  roleIds: number[];
};

export type TJoinedSettings = TSettings & {
  logo: TFile | null;
};

export type TInviteJoin = {
  userId: number;
  createdAt: number;
};

export type TJoinedInvite = TInvite & {
  creator: TJoinedPublicUser;
  role: { id: number; name: string; color: string } | null;
  joins: TInviteJoin[];
};
