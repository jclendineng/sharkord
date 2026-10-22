export * from './afk';
export * from './dms';
export * from './emojis';
export * from './locales';
export * from './metrics';
export * from './permissions';
export * from './polls';
export * from './retention';
export * from './soundboard';
export * from './stickers';
export * from './storage';
export * from './upload';
export * from './webhooks';

export const DEFAULT_MESSAGES_LIMIT = 100;
export const MESSAGE_MAX_LENGTH = 10_000;

// a reaction is either a unicode emoji (long ZWJ sequences included) or the
// name of a custom server emoji, which add-emoji caps at 32
export const REACTION_EMOJI_MAX_LENGTH = 32;

export const OWNER_ROLE_ID = 1;

export const TYPING_MS = 300;

export enum MessageNodeType {
  MENTION = 'mention',
  ROLE_MENTION = 'role-mention',
  CHANNEL_REFERENCE = 'channel-reference',
  PLUGIN_COMMAND = 'plugin-command',
  // written by @tiptap/extension-emoji, not by our own nodes
  EMOJI = 'emoji'
}

export enum DisconnectCode {
  UNEXPECTED = 1006,
  KICKED = 40000,
  BANNED = 40001,
  SERVER_SHUTDOWN = 40002
}

export const MAX_USER_NAME_LENGTH = 24;

// what /login answers, on the totp field, when the password is right and an authenticator code
// is still needed. the apps match it to show the code field
export const TOTP_REQUIRED_MESSAGE =
  'Enter the code from your authenticator app.';

// what someone on a network a moderator banned is told, at sign in and when joining
export const IP_BANNED_MESSAGE = 'This network is banned from the server.';

export const DELETED_USER_IDENTITY_AND_NAME = '__deleted_user__'; // this will be used as identity AND name, but in the interface we render as "Deleted"

export const DEFAULT_BITRATE = 6000; // kbps,
