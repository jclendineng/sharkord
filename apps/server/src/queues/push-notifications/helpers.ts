import {
  ChannelPermission,
  getPlainTextFromHtml,
  hasMention
} from '@sharkord/shared';
import { and, eq, inArray, ne } from 'drizzle-orm';
import { db } from '../../db';
import { getAffectedUserIdsForChannel } from '../../db/queries/channels';
import { getSettings } from '../../db/queries/server';
import {
  channelNotificationSettings,
  channels,
  messages,
  pushDevices,
  userRoles,
  users
} from '../../db/schema';

const BODY_MAX_LENGTH = 180;

type TPushMessage = {
  id: number;
  channelId: number;
  channelName: string;
  isDm: boolean;
  userId: number | null;
  pluginId: string | null;
  content: string | null;
  parentMessageId: number | null;
  replyToMessageId: number | null;
};

type TPushDevice = {
  id: number;
  userId: number;
  token: string;
  sandbox: boolean;
};

const getPushMessage = (messageId: number): TPushMessage | undefined =>
  db
    .select({
      id: messages.id,
      channelId: messages.channelId,
      channelName: channels.name,
      isDm: channels.isDm,
      userId: messages.userId,
      pluginId: messages.pluginId,
      content: messages.content,
      parentMessageId: messages.parentMessageId,
      replyToMessageId: messages.replyToMessageId
    })
    .from(messages)
    .innerJoin(channels, eq(channels.id, messages.channelId))
    .where(eq(messages.id, messageId))
    .limit(1)
    .get();

// a device belongs to a session: a banned user, or one whose sessions were ended since it
// registered, no longer receives anything on it. do not disturb silences every device
const getActiveDevices = (senderId: number | null) =>
  db
    .select({
      id: pushDevices.id,
      userId: pushDevices.userId,
      token: pushDevices.token,
      sandbox: pushDevices.sandbox
    })
    .from(pushDevices)
    .innerJoin(users, eq(users.id, pushDevices.userId))
    .where(
      and(
        eq(users.tokenVersion, pushDevices.tokenVersion),
        eq(users.banned, false),
        ne(users.presence, 'dnd'),
        senderId === null ? undefined : ne(pushDevices.userId, senderId)
      )
    )
    .all();

// mirrors what the web client notifies for: direct messages, mentions and replies, and only
// for people who can see the channel at all. a channel's notification setting overrides it
const getRecipientDevices = async (
  message: TPushMessage
): Promise<TPushDevice[]> => {
  const devices = await getActiveDevices(message.userId);

  if (devices.length === 0) return [];

  const deviceUserIds = [...new Set(devices.map(({ userId }) => userId))];

  const [roleRows, repliedTo, settingRows] = await Promise.all([
    db
      .select({ userId: userRoles.userId, roleId: userRoles.roleId })
      .from(userRoles)
      .where(inArray(userRoles.userId, deviceUserIds))
      .all(),
    message.replyToMessageId
      ? db
          .select({ userId: messages.userId })
          .from(messages)
          .where(eq(messages.id, message.replyToMessageId))
          .limit(1)
          .get()
      : undefined,
    db
      .select({
        userId: channelNotificationSettings.userId,
        level: channelNotificationSettings.level
      })
      .from(channelNotificationSettings)
      .where(
        and(
          eq(channelNotificationSettings.channelId, message.channelId),
          inArray(channelNotificationSettings.userId, deviceUserIds)
        )
      )
      .all()
  ]);

  const levelByUser = new Map(
    settingRows.map(({ userId, level }) => [userId, level])
  );

  const roleIdsByUser = new Map<number, number[]>();

  for (const { userId, roleId } of roleRows) {
    const roleIds = roleIdsByUser.get(userId) ?? [];

    roleIds.push(roleId);
    roleIdsByUser.set(userId, roleIds);
  }

  // muted sends nothing, mentions included. "all" sends every message
  const candidateIds = deviceUserIds.filter((userId) => {
    const level = levelByUser.get(userId);

    if (level === 'none') return false;
    if (level === 'all') return true;

    return (
      message.isDm ||
      userId === repliedTo?.userId ||
      hasMention(message.content, userId, roleIdsByUser.get(userId))
    );
  });

  if (candidateIds.length === 0) return [];

  const viewerIds = new Set(
    await getAffectedUserIdsForChannel(
      message.channelId,
      ChannelPermission.VIEW_CHANNEL
    )
  );

  return devices.filter(
    ({ userId }) => candidateIds.includes(userId) && viewerIds.has(userId)
  );
};

const buildPushPayload = async (message: TPushMessage) => {
  const [settings, sender] = await Promise.all([
    getSettings(),
    message.userId
      ? db
          .select({ name: users.name })
          .from(users)
          .where(eq(users.id, message.userId))
          .limit(1)
          .get()
      : undefined
  ]);

  const senderName = sender?.name ?? message.pluginId ?? 'Someone';
  const text = getPlainTextFromHtml(message.content ?? '').trim();

  let body = text || 'Sent an attachment';

  if (body.length > BODY_MAX_LENGTH) {
    body = `${body.slice(0, BODY_MAX_LENGTH - 1)}…`;
  }

  return {
    aps: {
      alert: {
        title: message.isDm
          ? senderName
          : `${senderName} in #${message.channelName}`,
        body
      },
      sound: 'default',
      'thread-id': `channel-${message.channelId}`
    },
    // the app holds several servers, channel ids alone are ambiguous across them
    serverId: settings.serverId,
    channelId: message.channelId,
    messageId: message.id,
    parentMessageId: message.parentMessageId
  };
};

export { buildPushPayload, getPushMessage, getRecipientDevices };
