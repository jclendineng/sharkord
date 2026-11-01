// what this fork adds over upstream sharkord, sent in /info so the apps can tell the two apart.
// upstream sends no list, and an app shows none of these there. drop one here to turn it off
export enum ServerFeature {
  POLLS = 'polls',
  GIFS = 'gifs',
  STICKERS = 'stickers',
  SOUNDBOARD = 'soundboard',
  TWO_FACTOR = 'two-factor',
  DEVICE_SESSIONS = 'device-sessions',
  DEVICE_SIGN_IN = 'device-sign-in',
  GROUP_DMS = 'group-dms',
  FRIENDS = 'friends',
  PRESENCE = 'presence',
  NOTES = 'notes',
  MARK_UNREAD = 'mark-unread',
  MENTIONS = 'mentions',
  THREADS_LIST = 'threads-list',
  CHANNEL_NOTIFICATIONS = 'channel-notifications',
  PRIVACY = 'privacy',
  PASSWORD_RESET = 'password-reset',
  ROLE_ORDER = 'role-order',
  ONBOARDING = 'onboarding',
  IP_BANS = 'ip-bans',
  SEARCH_FILTERS = 'search-filters',
  PINNED_CHANNELS = 'pinned-channels',
  FILE_SIGNING = 'file-signing'
}

export const SERVER_FEATURES = Object.values(ServerFeature);
