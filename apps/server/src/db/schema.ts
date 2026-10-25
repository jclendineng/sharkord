import {
  DEFAULT_PROFILE_COLOR,
  PluginCapabilityMode,
  PluginCapabilityType,
  type TActivityLogDetailsMap,
  type TMessageMetadata,
  type TPluginMessageComponent
} from '@sharkord/shared';
import { sql } from 'drizzle-orm';
import {
  index,
  integer,
  primaryKey,
  sqliteTable,
  text,
  uniqueIndex,
  type AnySQLiteColumn
} from 'drizzle-orm/sqlite-core';

const files = sqliteTable(
  'files',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    name: text('name').notNull().unique(),
    originalName: text('original_name').notNull(),
    md5: text('md5').notNull(),
    userId: integer('user_id'),
    pluginId: text('plugin_id'),
    size: integer('size').notNull(),
    mimeType: text('mime_type').notNull(),
    extension: text('extension').notNull(),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [
    index('files_user_idx').on(t.userId),
    index('files_md5_idx').on(t.md5),
    index('files_created_idx').on(t.createdAt),
    index('files_name_idx').on(t.name)
  ]
);

const settings = sqliteTable(
  'settings',
  {
    name: text('name').notNull(),
    description: text('description'),
    password: text('password'),
    onlyAskForPasswordOnFirstJoin: integer(
      'only_ask_for_password_on_first_join',
      {
        mode: 'boolean'
      }
    ).notNull(),
    serverId: text('server_id').notNull(),
    secretToken: text('secret_token'),
    logoId: integer('logo_id').references(() => files.id, {
      onDelete: 'set null'
    }),
    allowNewUsers: integer('allow_new_users', { mode: 'boolean' }).notNull(),
    directMessagesEnabled: integer('direct_messages_enabled', {
      mode: 'boolean'
    }).notNull(),
    storageUploadEnabled: integer('storage_uploads_enabled', {
      mode: 'boolean'
    }).notNull(),
    storageQuota: integer('storage_quota').notNull(),
    storageUploadMaxFileSize: integer('storage_upload_max_file_size').notNull(),
    storageMaxAvatarSize: integer('storage_max_avatar_size').notNull(),
    storageMaxBannerSize: integer('storage_max_banner_size').notNull(),
    storageMaxFilesPerMessage: integer(
      'storage_max_files_per_message'
    ).notNull(),
    storageFileSharingInDirectMessages: integer(
      'storage_file_sharing_in_direct_messages',
      {
        mode: 'boolean'
      }
    ).notNull(),
    storageSpaceQuotaByUser: integer('storage_space_quota_by_user').notNull(),
    storageOverflowAction: text('storage_overflow_action').notNull(),
    enablePlugins: integer('enable_plugins', { mode: 'boolean' }).notNull(),
    enableSearch: integer('enable_search', { mode: 'boolean' }).notNull(),
    webRtcSimulcastEnabled: integer('web_rtc_simulcast_enabled', {
      mode: 'boolean'
    })
      .notNull()
      .default(false),
    showWelcomeDialog: integer('show_welcome_dialog', {
      mode: 'boolean'
    })
      .notNull()
      .default(true),
    reportEmail: text('report_email'),
    // the voice channel members silent for afkTimeoutSeconds are moved to, null turns it off.
    // no foreign key: sqlite drops on delete set null from an added column, so the reference
    // would block deleting the channel. a channel that is gone simply turns afk off
    afkChannelId: integer('afk_channel_id'),
    afkTimeoutSeconds: integer('afk_timeout_seconds').notNull().default(300),
    // the klipy api key the server searches gifs with, never sent to members
    klipyApiKey: text('klipy_api_key'),
    // the freesound api key managers search sounds with, never sent to members
    freesoundApiKey: text('freesound_api_key'),
    pushShowMessageContent: integer('push_show_message_content', {
      mode: 'boolean'
    })
      .notNull()
      .default(true),
    // link previews may be fetched from addresses on the server's own network. off by default:
    // any member could otherwise have the server load pages only it can reach
    linkPreviewsPrivateNetwork: integer('link_previews_private_network', {
      mode: 'boolean'
    })
      .notNull()
      .default(false),
    storageSignedUrlsTtlSeconds: integer(
      'storage_signed_urls_ttl_seconds'
    ).notNull(),
    storageImageOptimizationEnabled: integer(
      'storage_image_optimization_enabled',
      {
        mode: 'boolean'
      }
    )
      .notNull()
      .default(false),
    storageImageOptimizationQuality: integer(
      'storage_image_optimization_quality'
    )
      .notNull()
      .default(80),
    // the rules a new member accepts: reacting to this message gives them the onboarding role,
    // which is what the server's public channels are opened to
    onboardingMessageId: integer('onboarding_message_id').references(
      (): AnySQLiteColumn => messages.id,
      { onDelete: 'set null' }
    ),
    onboardingRoleId: integer('onboarding_role_id').references(
      (): AnySQLiteColumn => roles.id,
      { onDelete: 'set null' }
    ),
    // reacting also takes away the role new members start with, when that role only stands for
    // not having accepted yet. off, since a default role can carry everyday permissions too
    onboardingRemovesDefaultRole: integer('onboarding_removes_default_role', {
      mode: 'boolean'
    })
      .notNull()
      .default(false)
  },
  (t) => [
    index('settings_server_idx').on(t.serverId),
    uniqueIndex('settings_server_unique_idx').on(t.serverId),
    uniqueIndex('settings_single_row_idx').on(sql`(1)`)
  ]
);

const roles = sqliteTable(
  'roles',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    name: text('name').notNull(),
    color: text('color').notNull().default('#ffffff'),
    isPersistent: integer('is_persistent', { mode: 'boolean' }).notNull(),
    isDefault: integer('is_default', { mode: 'boolean' }).notNull(),
    storageQuotaOverrideEnabled: integer('storage_quota_override_enabled', {
      mode: 'boolean'
    })
      .notNull()
      .default(false),
    storageSpaceQuota: integer('storage_space_quota').notNull().default(0),
    // discord's role order, lowest first: it picks the role a member shows as and heads the
    // member list. the owner's role stays on top and the default one at the bottom
    position: integer('position').notNull().default(0),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [index('roles_position_idx').on(t.position)]
);

const categories = sqliteTable(
  'categories',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    name: text('name').notNull(),
    position: integer('position').notNull(),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [index('categories_position_idx').on(t.position)]
);

const channels = sqliteTable(
  'channels',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    type: text('type').notNull(),
    name: text('name').notNull(),
    topic: text('topic'),
    private: integer('private', { mode: 'boolean' }).notNull().default(false),
    // messages older than this many days are deleted, pinned ones kept. null keeps everything
    retentionDays: integer('retention_days'),
    isDm: integer('is_dm_channel', { mode: 'boolean' })
      .notNull()
      .default(false),
    position: integer('position').notNull(),
    categoryId: integer('category_id').references(() => categories.id, {
      onDelete: 'cascade'
    }),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [
    index('channels_position_idx').on(t.position),
    index('channels_type_idx').on(t.type),
    index('channels_category_position_idx').on(t.categoryId, t.position)
  ]
);

const users = sqliteTable(
  'users',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    identity: text('identity').unique().notNull(),
    password: text('password').notNull(),
    name: text('name').notNull(),
    avatarId: integer('avatar_id').references(() => files.id, {
      onDelete: 'set null'
    }),
    bannerId: integer('banner_id').references(() => files.id, {
      onDelete: 'set null'
    }),
    bio: text('bio'),
    banned: integer('banned', { mode: 'boolean' }).notNull().default(false),
    banReason: text('ban_reason'),
    bannedAt: integer('banned_at'),
    tokenVersion: integer('token_version').notNull().default(0),
    // whether people on the server can start a new direct message with this user
    allowDirectMessages: integer('allow_direct_messages', { mode: 'boolean' })
      .notNull()
      .default(true),
    // the status the user picked, shown while they are connected. invisible reads as
    // offline to everyone else, so it never leaves the server
    presence: text('presence', { enum: ['online', 'idle', 'dnd', 'invisible'] })
      .notNull()
      .default('online'),
    customStatus: text('custom_status'),
    oidcSub: text('oidc_sub').unique(),
    oidcIssuer: text('oidc_issuer'),
    passwordSet: integer('password_set', { mode: 'boolean' })
      .notNull()
      .default(true),
    profileColor: text('profile_color')
      .notNull()
      .default(DEFAULT_PROFILE_COLOR),
    lastLoginAt: integer('last_login_at')
      .notNull()
      .$defaultFn(() => Date.now()),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [
    uniqueIndex('users_identity_idx').on(t.identity),
    index('users_name_idx').on(t.name),
    index('users_last_login_idx').on(t.lastLoginAt)
  ]
);

const userRoles = sqliteTable(
  'user_roles',
  {
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    roleId: integer('role_id')
      .notNull()
      .references(() => roles.id, { onDelete: 'cascade' }),
    createdAt: integer('created_at').notNull()
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.roleId] }),
    index('user_roles_role_idx').on(t.roleId)
  ]
);

// an address outside the server can post to a channel through, discord's incoming webhook.
// only a hash of the token is kept, the url carrying it is shown once when it is made
const webhooks = sqliteTable(
  'webhooks',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    channelId: integer('channel_id')
      .notNull()
      .references(() => channels.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    tokenHash: text('token_hash').notNull(),
    createdBy: integer('created_by').references(() => users.id, {
      onDelete: 'set null'
    }),
    createdAt: integer('created_at').notNull()
  },
  (t) => [index('webhooks_channel_idx').on(t.channelId)]
);

// an authenticator app as a second step at password sign in. kept apart from users so the
// secret can never ride along a select of a user row. enabledAt is null while setup waits for
// its first code, and recovery codes are stored as hashes, each spent once
const userTotp = sqliteTable('user_totp', {
  userId: integer('user_id')
    .primaryKey()
    .references(() => users.id, { onDelete: 'cascade' }),
  secret: text('secret').notNull(),
  // the last 30 second step a code was accepted for, so a code cannot be used twice
  lastStep: integer('last_step').notNull().default(0),
  recoveryCodeHashes: text('recovery_code_hashes', { mode: 'json' })
    .$type<string[]>()
    .notNull()
    .default([]),
  enabledAt: integer('enabled_at'),
  createdAt: integer('created_at').notNull()
});

// one time links a moderator hands someone who forgot their password, there being no email to
// send a reset to. only a hash of the token is kept, and using it signs every session out
const passwordResets = sqliteTable(
  'password_resets',
  {
    tokenHash: text('token_hash').primaryKey(),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdBy: integer('created_by').references(() => users.id, {
      onDelete: 'set null'
    }),
    expiresAt: integer('expires_at').notNull(),
    createdAt: integer('created_at').notNull()
  },
  (t) => [index('password_resets_user_idx').on(t.userId)]
);

// addresses a moderator banned along with an account. the ban outlives the account, so a
// deleted user's addresses stay banned, and unbanning the account lifts them
const ipBans = sqliteTable(
  'ip_bans',
  {
    ip: text('ip').primaryKey(),
    userId: integer('user_id').references(() => users.id, {
      onDelete: 'set null'
    }),
    createdAt: integer('created_at').notNull()
  },
  (t) => [index('ip_bans_user_idx').on(t.userId)]
);

const logins = sqliteTable(
  'logins',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    userAgent: text('user_agent'),
    os: text('os'),
    device: text('device'),
    ip: text('ip'),
    hostname: text('hostname'),
    city: text('city'),
    region: text('region'),
    country: text('country'),
    loc: text('loc'),
    org: text('org'),
    postal: text('postal'),
    timezone: text('timezone'),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [
    index('logins_ip_idx').on(t.ip),
    index('logins_created_idx').on(t.createdAt),
    index('logins_user_created_idx').on(t.userId, t.createdAt)
  ]
);

const messages = sqliteTable(
  'messages',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    content: text('content'),
    // nullable because plugin-authored messages have no user, see plugins/actions. the
    // cascade is delete-user's `wipe: true` branch; `wipe: false` reassigns to the deleted
    // user placeholder first, so nothing is left to cascade
    userId: integer('user_id').references(() => users.id, {
      onDelete: 'cascade'
    }),
    pluginId: text('plugin_id'),
    // the name an incoming webhook posted under, kept with the message as discord does, so a
    // renamed or deleted webhook leaves its old messages as they were
    webhookName: text('webhook_name'),
    pluginComponents: text('plugin_components', {
      mode: 'json'
    }).$type<TPluginMessageComponent[] | null>(),
    channelId: integer('channel_id')
      .notNull()
      .references(() => channels.id, { onDelete: 'cascade' }),
    parentMessageId: integer('parent_message_id').references(
      (): AnySQLiteColumn => messages.id,
      { onDelete: 'cascade' }
    ),
    replyToMessageId: integer('reply_to_message_id').references(
      (): AnySQLiteColumn => messages.id,
      { onDelete: 'set null' }
    ),
    editable: integer('editable', { mode: 'boolean' }).default(true),
    metadata: text('metadata', { mode: 'json' }).$type<TMessageMetadata[]>(),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at'),
    pinned: integer('pinned', { mode: 'boolean' }).default(false),
    pinnedAt: integer('pinned_at'),
    pinnedBy: integer('pinned_by').references(() => users.id, {
      onDelete: 'set null'
    }),
    editedAt: integer('edited_at'),
    editedBy: integer('edited_by').references(() => users.id, {
      onDelete: 'set null'
    }),
    // a deleted sticker leaves its message behind, showing that it is gone
    stickerId: integer('sticker_id').references(
      (): AnySQLiteColumn => stickers.id,
      { onDelete: 'set null' }
    )
  },
  (t) => [
    index('messages_user_idx').on(t.userId),
    index('messages_created_idx').on(t.createdAt),
    index('messages_channel_created_idx').on(t.channelId, t.createdAt),
    index('messages_channel_parent_created_idx').on(
      t.channelId,
      t.parentMessageId,
      t.createdAt
    ),
    index('messages_parent_idx').on(t.parentMessageId),
    index('messages_sticker_idx').on(t.stickerId),
    index('messages_reply_to_idx').on(t.replyToMessageId),
    index('messages_parent_channel_id_idx').on(
      t.parentMessageId,
      t.channelId,
      t.id
    )
  ]
);

const messageFiles = sqliteTable(
  'message_files',
  {
    messageId: integer('message_id')
      .notNull()
      .references(() => messages.id, { onDelete: 'cascade' }),
    fileId: integer('file_id')
      .notNull()
      .references(() => files.id, { onDelete: 'cascade' }),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [
    primaryKey({ columns: [t.messageId, t.fileId] }),
    index('message_files_msg_idx').on(t.messageId),
    index('message_files_file_idx').on(t.fileId)
  ]
);

const rolePermissions = sqliteTable(
  'role_permissions',
  {
    roleId: integer('role_id')
      .notNull()
      .references(() => roles.id, { onDelete: 'cascade' }),
    permission: text('permission').notNull(),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [
    primaryKey({ columns: [t.roleId, t.permission] }),
    index('role_permissions_permission_idx').on(t.permission)
  ]
);

const emojis = sqliteTable(
  'emojis',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    name: text('name').notNull().unique(),
    fileId: integer('file_id')
      .notNull()
      .references(() => files.id, { onDelete: 'cascade' }),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [
    index('emojis_user_idx').on(t.userId),
    index('emojis_file_idx').on(t.fileId),
    uniqueIndex('emojis_name_idx').on(t.name)
  ]
);

const messageReactions = sqliteTable(
  'message_reactions',
  {
    messageId: integer('message_id')
      .notNull()
      .references(() => messages.id, { onDelete: 'cascade' }),
    userId: integer('user_id').references(() => users.id, {
      onDelete: 'cascade'
    }),
    pluginId: text('plugin_id'),
    emoji: text('emoji').notNull(),
    fileId: integer('file_id').references(() => files.id, {
      onDelete: 'set null'
    }),
    createdAt: integer('created_at').notNull()
  },
  (t) => [
    primaryKey({ columns: [t.messageId, t.userId, t.emoji] }),
    uniqueIndex('reaction_msg_emoji_plugin_unique_idx').on(
      t.messageId,
      t.emoji,
      t.pluginId
    ),
    index('reaction_emoji_idx').on(t.emoji),
    index('reaction_user_idx').on(t.userId),
    index('reaction_msg_emoji_idx').on(t.messageId, t.emoji)
  ]
);

const stickers = sqliteTable(
  'stickers',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    name: text('name').notNull(),
    description: text('description'),
    fileId: integer('file_id')
      .notNull()
      .references(() => files.id, { onDelete: 'cascade' }),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [
    index('stickers_user_idx').on(t.userId),
    index('stickers_file_idx').on(t.fileId)
  ]
);

// a server's soundboard. a sound picked from the library keeps the library's key, so the
// picker can show which of them the server already has
const soundboardSounds = sqliteTable(
  'soundboard_sounds',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    name: text('name').notNull(),
    emoji: text('emoji'),
    // a percentage, see SOUND_MAX_VOLUME
    volume: integer('volume').notNull().default(100),
    // where it came from: a library key, or freesound:<id> for one added from a search
    libraryKey: text('library_key'),
    // who made it and under what license, shown wherever the sound is managed
    attribution: text('attribution'),
    fileId: integer('file_id')
      .notNull()
      .references(() => files.id, { onDelete: 'cascade' }),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [
    index('soundboard_sounds_user_idx').on(t.userId),
    index('soundboard_sounds_file_idx').on(t.fileId),
    uniqueIndex('soundboard_sounds_library_key_idx').on(t.libraryKey)
  ]
);

// a message can carry one poll, its answers in order and who picked which
const polls = sqliteTable('polls', {
  messageId: integer('message_id')
    .primaryKey()
    .references(() => messages.id, { onDelete: 'cascade' }),
  question: text('question').notNull(),
  allowMultiple: integer('allow_multiple', { mode: 'boolean' }).notNull(),
  expiresAt: integer('expires_at').notNull(),
  endedAt: integer('ended_at'),
  createdAt: integer('created_at').notNull()
});

const pollAnswers = sqliteTable(
  'poll_answers',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    messageId: integer('message_id')
      .notNull()
      .references(() => polls.messageId, { onDelete: 'cascade' }),
    position: integer('position').notNull(),
    text: text('text').notNull(),
    emoji: text('emoji')
  },
  (t) => [
    index('poll_answers_message_position_idx').on(t.messageId, t.position)
  ]
);

const pollVotes = sqliteTable(
  'poll_votes',
  {
    answerId: integer('answer_id')
      .notNull()
      .references(() => pollAnswers.id, { onDelete: 'cascade' }),
    messageId: integer('message_id')
      .notNull()
      .references(() => polls.messageId, { onDelete: 'cascade' }),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdAt: integer('created_at').notNull()
  },
  (t) => [
    primaryKey({ columns: [t.answerId, t.userId] }),
    index('poll_votes_message_user_idx').on(t.messageId, t.userId),
    index('poll_votes_user_idx').on(t.userId)
  ]
);

const invites = sqliteTable(
  'invites',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    code: text('code').notNull().unique(),
    creatorId: integer('creator_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    roleId: integer('role_id').references(() => roles.id, {
      onDelete: 'set null'
    }),
    maxUses: integer('max_uses'),
    uses: integer('uses').notNull().default(0),
    expiresAt: integer('expires_at'),
    createdAt: integer('created_at').notNull(),
    // a deleted invite stops working but stays, so who joined with it is still known
    deletedAt: integer('deleted_at')
  },
  (t) => [
    uniqueIndex('invites_code_idx').on(t.code),
    index('invites_creator_idx').on(t.creatorId),
    index('invites_expires_idx').on(t.expiresAt)
  ]
);

// who signed up with which invite. one row per account, written with the account
const inviteUses = sqliteTable(
  'invite_uses',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    inviteId: integer('invite_id')
      .notNull()
      .references(() => invites.id, { onDelete: 'cascade' }),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdAt: integer('created_at').notNull()
  },
  (t) => [
    index('invite_uses_invite_created_idx').on(t.inviteId, t.createdAt),
    uniqueIndex('invite_uses_user_idx').on(t.userId)
  ]
);

const activityLog = sqliteTable(
  'activity_log',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    userId: integer('user_id').references(() => users.id, {
      onDelete: 'cascade'
    }),
    type: text('type').notNull(),
    details: text('details', { mode: 'json' }).$type<
      TActivityLogDetailsMap[keyof TActivityLogDetailsMap]
    >(),
    ip: text('ip'),
    createdAt: integer('created_at').notNull()
  },
  (t) => [
    index('activity_log_created_idx').on(t.createdAt),
    index('activity_log_user_created_idx').on(t.userId, t.createdAt),
    index('activity_log_type_created_idx').on(t.type, t.createdAt)
  ]
);

const channelRolePermissions = sqliteTable(
  'channel_role_permissions',
  {
    channelId: integer('channel_id')
      .notNull()
      .references(() => channels.id, { onDelete: 'cascade' }),
    roleId: integer('role_id')
      .notNull()
      .references(() => roles.id, { onDelete: 'cascade' }),
    permission: text('permission').notNull(),
    allow: integer('allow', { mode: 'boolean' }).notNull(),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [
    primaryKey({ columns: [t.channelId, t.roleId, t.permission] }),
    index('channel_role_permissions_role_idx').on(t.roleId),
    index('channel_role_permissions_channel_perm_idx').on(
      t.channelId,
      t.permission
    ),
    index('channel_role_permissions_role_perm_idx').on(t.roleId, t.permission)
  ]
);

const channelUserPermissions = sqliteTable(
  'channel_user_permissions',
  {
    channelId: integer('channel_id')
      .notNull()
      .references(() => channels.id, { onDelete: 'cascade' }),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    permission: text('permission').notNull(),
    allow: integer('allow', { mode: 'boolean' }).notNull(),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at')
  },
  (t) => [
    primaryKey({ columns: [t.channelId, t.userId, t.permission] }),
    index('channel_user_permissions_user_idx').on(t.userId),
    index('channel_user_permissions_channel_perm_idx').on(
      t.channelId,
      t.permission
    ),
    index('channel_user_permissions_user_perm_idx').on(t.userId, t.permission)
  ]
);

const channelReadStates = sqliteTable(
  'channel_read_states',
  {
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    channelId: integer('channel_id')
      .notNull()
      .references(() => channels.id, { onDelete: 'cascade' }),
    lastReadMessageId: integer('last_read_message_id'),
    lastReadAt: integer('last_read_at').notNull()
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.channelId] }),
    index('channel_read_states_channel_idx').on(t.channelId)
  ]
);

const directMessages = sqliteTable(
  'direct_messages',
  {
    channelId: integer('channel_id')
      .notNull()
      .references(() => channels.id, { onDelete: 'cascade' }),
    userOneId: integer('user_one_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    userTwoId: integer('user_two_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdAt: integer('created_at').notNull()
  },
  (t) => [
    primaryKey({ columns: [t.channelId] }),
    uniqueIndex('direct_messages_pair_unique_idx').on(t.userOneId, t.userTwoId),
    index('direct_messages_user_one_idx').on(t.userOneId),
    index('direct_messages_user_two_idx').on(t.userTwoId)
  ]
);

// two people who are friends, or one asked and the other has not answered yet. the pair is
// stored smaller id first so it exists once whoever asked
const friendships = sqliteTable(
  'friendships',
  {
    userOneId: integer('user_one_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    userTwoId: integer('user_two_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    requesterId: integer('requester_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    status: text('status', { enum: ['pending', 'accepted'] }).notNull(),
    createdAt: integer('created_at').notNull(),
    acceptedAt: integer('accepted_at')
  },
  (t) => [
    primaryKey({ columns: [t.userOneId, t.userTwoId] }),
    index('friendships_user_two_idx').on(t.userTwoId)
  ]
);

// a direct message between more than two people, as discord's group dms: the channel is a dm
// channel like any other, these say who is in it and what it is called
const groupDms = sqliteTable('group_dms', {
  channelId: integer('channel_id')
    .primaryKey()
    .references(() => channels.id, { onDelete: 'cascade' }),
  name: text('name'),
  ownerId: integer('owner_id').references(() => users.id, {
    onDelete: 'set null'
  }),
  createdAt: integer('created_at').notNull()
});

const groupDmMembers = sqliteTable(
  'group_dm_members',
  {
    channelId: integer('channel_id')
      .notNull()
      .references(() => channels.id, { onDelete: 'cascade' }),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    addedAt: integer('added_at').notNull()
  },
  (t) => [
    primaryKey({ columns: [t.channelId, t.userId] }),
    index('group_dm_members_user_idx').on(t.userId)
  ]
);

// signing a new device in from one already signed in, by a qr code it shows: the new device
// scans it and claims it, then the signed in one approves it. only hashes of the two secrets are
// kept, the code in the qr code and the key the claiming device proves itself with
const loginLinks = sqliteTable(
  'login_links',
  {
    id: text('id').primaryKey(),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    secretHash: text('secret_hash').notNull(),
    claimKeyHash: text('claim_key_hash'),
    // waiting, claimed, approved or denied
    status: text('status').notNull(),
    claimedOs: text('claimed_os'),
    claimedDevice: text('claimed_device'),
    claimedIp: text('claimed_ip'),
    createdAt: integer('created_at').notNull(),
    expiresAt: integer('expires_at').notNull()
  },
  (t) => [index('login_links_user_idx').on(t.userId)]
);

// the other way round, for a device without a camera: it asks to be signed in and shows a qr
// code, and a device already signed in scans that and approves it for its own account. only the
// asking device holds the poll key that collects the session
const loginRequests = sqliteTable(
  'login_requests',
  {
    id: text('id').primaryKey(),
    secretHash: text('secret_hash').notNull(),
    pollKeyHash: text('poll_key_hash').notNull(),
    // set by whoever approves it
    userId: integer('user_id').references(() => users.id, {
      onDelete: 'cascade'
    }),
    // waiting, approved or denied
    status: text('status').notNull(),
    requestOs: text('request_os'),
    requestDevice: text('request_device'),
    requestIp: text('request_ip'),
    createdAt: integer('created_at').notNull(),
    expiresAt: integer('expires_at').notNull()
  },
  (t) => [index('login_requests_expires_idx').on(t.expiresAt)]
);

// what someone wrote about another member for themselves, as discord's note on a profile: only
// its author ever reads it
const userNotes = sqliteTable(
  'user_notes',
  {
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    targetUserId: integer('target_user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    note: text('note').notNull(),
    updatedAt: integer('updated_at').notNull()
  },
  (t) => [primaryKey({ columns: [t.userId, t.targetUserId] })]
);

// a direct message one participant closed: hidden from their list until a message newer than
// the close arrives or they open it again, as discord's close dm
const directMessageClosures = sqliteTable(
  'direct_message_closures',
  {
    channelId: integer('channel_id')
      .notNull()
      .references(() => channels.id, { onDelete: 'cascade' }),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    closedAt: integer('closed_at').notNull()
  },
  (t) => [
    primaryKey({ columns: [t.channelId, t.userId] }),
    index('direct_message_closures_user_idx').on(t.userId)
  ]
);

const oidcTransactions = sqliteTable(
  'oidc_transactions',
  {
    state: text('state').primaryKey(),
    nonce: text('nonce').notNull(),
    codeVerifier: text('code_verifier').notNull(),
    redirectUri: text('redirect_uri').notNull(),
    appChallenge: text('app_challenge'),
    inviteCode: text('invite_code'),
    expiresAt: integer('expires_at').notNull()
  },
  (t) => [index('oidc_transactions_expires_idx').on(t.expiresAt)]
);

const oidcHandoffs = sqliteTable(
  'oidc_handoffs',
  {
    code: text('code').primaryKey(),
    token: text('token').notNull(),
    state: text('state').notNull(),
    appChallenge: text('app_challenge'),
    expiresAt: integer('expires_at').notNull()
  },
  (t) => [index('oidc_handoffs_expires_idx').on(t.expiresAt)]
);

// tokenVersion is copied from the user at registration, so a kick or a password change that
// ends the user's sessions also stops pushes to the devices those sessions registered
// one row per login, so a single device can be signed out. the id travels in the token, and
// a token whose row is gone is refused. device and location are kept up to date by each join
const sessions = sqliteTable(
  'sessions',
  {
    id: text('id').primaryKey(),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    os: text('os'),
    device: text('device'),
    userAgent: text('user_agent'),
    ip: text('ip'),
    city: text('city'),
    region: text('region'),
    country: text('country'),
    createdAt: integer('created_at').notNull(),
    lastActiveAt: integer('last_active_at').notNull()
  },
  (t) => [index('sessions_user_active_idx').on(t.userId, t.lastActiveAt)]
);

// a person's choice for one channel. no row means the default: mentions and replies, and
// every message in a direct message
const channelNotificationSettings = sqliteTable(
  'channel_notification_settings',
  {
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    channelId: integer('channel_id')
      .notNull()
      .references(() => channels.id, { onDelete: 'cascade' }),
    level: text('level', { enum: ['all', 'mentions', 'none'] }).notNull(),
    // a mute for a while, as discord's "for 1 hour": past it the channel is back to the default.
    // null mutes until it is turned back on
    mutedUntil: integer('muted_until'),
    updatedAt: integer('updated_at').notNull()
  },
  (t) => [
    primaryKey({ columns: [t.channelId, t.userId] }),
    index('channel_notification_settings_user_idx').on(t.userId)
  ]
);

// channels and conversations a user pinned to the top of their list, in the order pinned. kept on
// the server so every device of the account shows the same ones
const channelPins = sqliteTable(
  'channel_pins',
  {
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    channelId: integer('channel_id')
      .notNull()
      .references(() => channels.id, { onDelete: 'cascade' }),
    createdAt: integer('created_at').notNull()
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.channelId] }),
    index('channel_pins_user_created_idx').on(t.userId, t.createdAt)
  ]
);

const pushDevices = sqliteTable(
  'push_devices',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    // the apns device token, or for a device behind the push relay the relay's id for it,
    // which never reveals the token
    token: text('token').notNull(),
    tokenVersion: integer('token_version').notNull(),
    // signing that session out removes the device with it. null for one registered by a token
    // from before sessions existed
    sessionId: text('session_id').references(() => sessions.id, {
      onDelete: 'cascade'
    }),
    // a development build's token is only accepted by the apns sandbox
    sandbox: integer('sandbox', { mode: 'boolean' }).notNull().default(false),
    // set together for a device behind the push relay, null for one apns is sent to directly
    relayTicket: text('relay_ticket'),
    encryptionKey: text('encryption_key'),
    createdAt: integer('created_at').notNull()
  },
  (t) => [
    uniqueIndex('push_devices_token_idx').on(t.token),
    index('push_devices_user_idx').on(t.userId)
  ]
);

const pluginData = sqliteTable('plugin_data', {
  pluginId: text('plugin_id').notNull().primaryKey(),
  enabled: integer('enabled', { mode: 'boolean' }).notNull().default(false),
  settings: text('settings', { mode: 'json' })
    .$type<Record<string, unknown>>()
    .notNull()
    .default({}),
  version: text('version')
});

const pluginUserData = sqliteTable(
  'plugin_user_data',
  {
    pluginId: text('plugin_id').notNull(),
    userId: integer('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    data: text('data', { mode: 'json' })
      .$type<Record<string, unknown>>()
      .notNull()
      .default({}),
    updatedAt: integer('updated_at').notNull()
  },
  (t) => [
    primaryKey({ columns: [t.pluginId, t.userId] }),
    index('plugin_user_data_user_idx').on(t.userId)
  ]
);

const pluginStorage = sqliteTable(
  'plugin_storage',
  {
    pluginId: text('plugin_id').notNull(),
    key: text('key').notNull(),
    value: text('value', { mode: 'json' }).notNull(),
    updatedAt: integer('updated_at').notNull()
  },
  (t) => [primaryKey({ columns: [t.pluginId, t.key] })]
);

const pluginCapabilities = sqliteTable(
  'plugin_capabilities',
  {
    pluginId: text('plugin_id').notNull(),
    type: text('type').$type<PluginCapabilityType>().notNull(),
    name: text('name').notNull(),
    mode: text('mode')
      .$type<PluginCapabilityMode>()
      .notNull()
      .default(PluginCapabilityMode.PUBLIC),
    updatedAt: integer('updated_at').notNull()
  },
  (t) => [primaryKey({ columns: [t.pluginId, t.type, t.name] })]
);

const pluginCapabilityRoles = sqliteTable(
  'plugin_capability_roles',
  {
    pluginId: text('plugin_id').notNull(),
    type: text('type').notNull(),
    name: text('name').notNull(),
    roleId: integer('role_id')
      .notNull()
      .references(() => roles.id, { onDelete: 'cascade' }),
    createdAt: integer('created_at').notNull()
  },
  (t) => [
    primaryKey({ columns: [t.pluginId, t.type, t.name, t.roleId] }),
    index('plugin_capability_roles_role_idx').on(t.roleId)
  ]
);

export {
  activityLog,
  categories,
  channelNotificationSettings,
  channelPins,
  channelReadStates,
  channelRolePermissions,
  channels,
  channelUserPermissions,
  directMessageClosures,
  directMessages,
  emojis,
  files,
  friendships,
  groupDmMembers,
  groupDms,
  invites,
  inviteUses,
  ipBans,
  loginLinks,
  loginRequests,
  logins,
  messageFiles,
  messageReactions,
  messages,
  oidcHandoffs,
  oidcTransactions,
  passwordResets,
  pluginCapabilities,
  pluginCapabilityRoles,
  pluginData,
  pluginStorage,
  pluginUserData,
  pollAnswers,
  polls,
  pollVotes,
  pushDevices,
  rolePermissions,
  roles,
  sessions,
  settings,
  soundboardSounds,
  stickers,
  userNotes,
  userRoles,
  users,
  userTotp,
  webhooks
};
