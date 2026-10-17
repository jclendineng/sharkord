import {
  ActivityLogType,
  CHANNEL_RETENTION_MAX_DAYS,
  CHANNEL_RETENTION_MIN_DAYS,
  ChannelPermission,
  ChannelType,
  OWNER_ROLE_ID,
  type TBeforeChannelCreatePayload,
  type TBeforeChannelCreateUpdate,
  type TBeforeChannelDeletePayload,
  type TChannel
} from '@sharkord/shared';
import { and, asc, desc, eq, inArray, ne } from 'drizzle-orm';
import { z } from 'zod';
import { db } from '../db';
import { reorderPositions } from '../db/mutations/positions';
import { publishChannel, publishChannelAccessChange } from '../db/publishers';
import { getAffectedOnlineUserIdsForChannel } from '../db/queries/channels';
import { isDirectMessageChannel } from '../db/queries/dms';
import {
  categories,
  channelRolePermissions,
  channels,
  roles
} from '../db/schema';
import { pluginManager } from '../plugins';
import { eventBus } from '../plugins/event-bus';
import { runHook } from '../plugins/run-hook';
import { enqueueActivityLog } from '../queues/activity-log';
import { VoiceRuntime } from '../runtimes/voice';
import { invariant } from '../utils/invariant';
import { enforceVoicePermissions } from './enforce-voice-permissions';

const zChannelName = z.string().min(1).max(27);
const zChannelTopic = z.string().max(128).nullable();

const zCreateChannel = z.object({
  name: zChannelName,
  type: z.enum(ChannelType),
  categoryId: z.number(),
  private: z.boolean().optional()
});

const zRetentionDays = z
  .number()
  .int()
  .min(CHANNEL_RETENTION_MIN_DAYS)
  .max(CHANNEL_RETENTION_MAX_DAYS)
  .nullable();

const zUpdateChannel = z.object({
  name: zChannelName.min(2).optional(),
  topic: zChannelTopic.optional(),
  private: z.boolean().optional(),
  retentionDays: zRetentionDays.optional()
});

type TCreateChannel = z.infer<typeof zCreateChannel>;
type TUpdateChannel = z.infer<typeof zUpdateChannel>;

const createChannel = async (
  input: TCreateChannel,
  userId: number | null
): Promise<TChannel> => {
  const values = zCreateChannel.parse(input);

  const category = await db
    .select({ id: categories.id })
    .from(categories)
    .where(eq(categories.id, values.categoryId))
    .limit(1)
    .get();

  invariant(category, {
    code: 'NOT_FOUND',
    message: 'Category not found'
  });

  const { name } = await runHook<
    TBeforeChannelCreatePayload,
    TBeforeChannelCreateUpdate
  >({
    entries: pluginManager.getHooks('beforeChannelCreate'),
    payload: {
      name: values.name,
      type: values.type,
      categoryId: values.categoryId,
      userId: userId ?? undefined
    },
    normalize: (payload, pluginId) => {
      invariant(payload.name.trim().length > 0, {
        code: 'BAD_REQUEST',
        message: `Plugin '${pluginId}' replaced this channel name with nothing.`
      });

      return payload;
    }
  });

  const channel = db.transaction((tx) => {
    const maxPositionChannel = tx
      .select({ position: channels.position })
      .from(channels)
      .orderBy(desc(channels.position))
      .where(eq(channels.categoryId, values.categoryId))
      .limit(1)
      .get();

    return tx
      .insert(channels)
      .values({
        position:
          maxPositionChannel?.position !== undefined
            ? maxPositionChannel.position + 1
            : 0,
        name,
        type: values.type,
        private: values.private ?? false,
        categoryId: values.categoryId,
        createdAt: Date.now()
      })
      .returning()
      .get();
  });

  if (channel.type === ChannelType.VOICE) {
    const runtime = new VoiceRuntime(channel.id);

    try {
      await runtime.init();
    } catch (error) {
      await db.delete(channels).where(eq(channels.id, channel.id));

      throw error;
    }
  }

  publishChannel(channel.id, 'create');

  eventBus.emit('channel:created', {
    channelId: channel.id,
    name: channel.name,
    type: channel.type,
    categoryId: channel.categoryId
  });

  enqueueActivityLog({
    type: ActivityLogType.CREATED_CHANNEL,
    userId,
    details: {
      channelId: channel.id,
      channelName: channel.name,
      type: channel.type as ChannelType
    }
  });

  return channel as TChannel;
};

const assertNotDirectMessage = async (channelId: number, action: string) => {
  const isDmChannel = await isDirectMessageChannel(channelId);

  invariant(!isDmChannel, {
    code: 'FORBIDDEN',
    message: `Cannot ${action} DM channels`
  });
};

const updateChannel = async (
  channelId: number,
  input: TUpdateChannel,
  userId: number | null
) => {
  const parsed = zUpdateChannel.parse(input);

  await assertNotDirectMessage(channelId, 'update');

  const oldChannel = await db
    .select({ private: channels.private })
    .from(channels)
    .where(eq(channels.id, channelId))
    .get();

  invariant(oldChannel, {
    code: 'NOT_FOUND',
    message: 'Channel not found'
  });

  const values = {
    ...(parsed.name !== undefined && { name: parsed.name }),
    ...(parsed.topic !== undefined && { topic: parsed.topic }),
    ...(parsed.private !== undefined && { private: parsed.private }),
    ...(parsed.retentionDays !== undefined && {
      retentionDays: parsed.retentionDays
    })
  };

  invariant(Object.keys(values).length > 0, {
    code: 'BAD_REQUEST',
    message: 'Nothing to update.'
  });

  const updatedChannel = await db
    .update(channels)
    .set(values)
    .where(eq(channels.id, channelId))
    .returning()
    .get();

  // a channel that just became public or private reaches a different audience
  const ensureUserAccess = updatedChannel.private !== oldChannel.private;

  publishChannel(updatedChannel.id, 'update', ensureUserAccess);

  if (ensureUserAccess) {
    const runtime = VoiceRuntime.findById(updatedChannel.id);

    if (runtime) {
      const { users } = runtime.getState();

      await enforceVoicePermissions(users.map(({ userId }) => userId));
    }
  }

  eventBus.emit('channel:updated', {
    channelId: updatedChannel.id,
    name: updatedChannel.name,
    type: updatedChannel.type,
    categoryId: updatedChannel.categoryId
  });

  enqueueActivityLog({
    type: ActivityLogType.UPDATED_CHANNEL,
    userId,
    details: {
      channelId: updatedChannel.id,
      values: parsed
    }
  });
};

type TChannelToDelete = { id: number; name: string; type: string };

const runBeforeChannelDeleteHook = async (
  channel: TChannelToDelete,
  userId: number | null
) => {
  await runHook<TBeforeChannelDeletePayload, never>({
    entries: pluginManager.getHooks('beforeChannelDelete'),
    payload: {
      channelId: channel.id,
      name: channel.name,
      type: channel.type,
      userId: userId ?? undefined
    }
  });
};

const deleteChannel = async (channelId: number, userId: number | null) => {
  await assertNotDirectMessage(channelId, 'delete');

  const channel = await db
    .select({ name: channels.name, type: channels.type })
    .from(channels)
    .where(eq(channels.id, channelId))
    .limit(1)
    .get();

  invariant(channel, {
    code: 'NOT_FOUND',
    message: 'Channel not found'
  });

  await runBeforeChannelDeleteHook({ id: channelId, ...channel }, userId);

  const removedChannel = await db
    .delete(channels)
    .where(eq(channels.id, channelId))
    .returning()
    .get();

  invariant(removedChannel, {
    code: 'NOT_FOUND',
    message: 'Channel not found'
  });

  await VoiceRuntime.findById(removedChannel.id)?.destroy();

  publishChannel(removedChannel.id, 'delete');

  eventBus.emit('channel:deleted', {
    channelId: removedChannel.id,
    name: removedChannel.name
  });

  enqueueActivityLog({
    type: ActivityLogType.DELETED_CHANNEL,
    userId,
    details: {
      channelId: removedChannel.id,
      channelName: removedChannel.name
    }
  });
};

const MAX_REORDERED_CHANNELS = 500;

const reorderChannels = async (
  categoryId: number,
  channelIds: number[],
  userId: number | null
) => {
  invariant(channelIds.length <= MAX_REORDERED_CHANNELS, {
    code: 'BAD_REQUEST',
    message: `At most ${MAX_REORDERED_CHANNELS} channels can be reordered at once.`
  });

  const [category, requestedChannels] = await Promise.all([
    db
      .select({ id: categories.id })
      .from(categories)
      .where(eq(categories.id, categoryId))
      .limit(1)
      .get(),
    db
      .select({
        id: channels.id,
        categoryId: channels.categoryId,
        isDm: channels.isDm
      })
      .from(channels)
      .where(inArray(channels.id, channelIds))
  ]);

  invariant(category, {
    code: 'NOT_FOUND',
    message: 'Category not found'
  });

  invariant(
    requestedChannels.every((channel) => !channel.isDm),
    {
      code: 'FORBIDDEN',
      message: 'Cannot move DM channels into a category'
    }
  );

  const movedChannelIds = requestedChannels
    .filter((channel) => channel.categoryId !== categoryId)
    .map((channel) => channel.id);

  if (movedChannelIds.length > 0) {
    await db
      .update(channels)
      .set({ categoryId, updatedAt: Date.now() })
      .where(inArray(channels.id, movedChannelIds));
  }

  const existingCategoryChannels = await db
    .select({ id: channels.id })
    .from(channels)
    .where(eq(channels.categoryId, categoryId))
    .orderBy(asc(channels.position), asc(channels.id));

  const nextChannelOrder = await reorderPositions(
    channels,
    existingCategoryChannels.map((channel) => channel.id),
    channelIds
  );

  nextChannelOrder.forEach((channelId) => {
    publishChannel(channelId, 'update');
  });

  if (nextChannelOrder.length > 0) {
    enqueueActivityLog({
      type: ActivityLogType.REORDERED_CHANNELS,
      userId,
      details: {
        categoryId,
        channelIds: nextChannelOrder
      }
    });
  }
};

// the new member lounge's other half: every public server channel but the rules one turns
// private, open to every role except the default one, so a new member sees only the rules until
// reacting. a channel already private was set up by hand and keeps its own permissions, as does
// any rule a role already has on a channel that turns private
const closeChannelsToDefaultRole = async (
  exceptChannelId: number,
  userId: number
): Promise<number[]> => {
  const publicChannelIds = (
    await db
      .select({ id: channels.id })
      .from(channels)
      .where(
        and(
          eq(channels.private, false),
          eq(channels.isDm, false),
          ne(channels.id, exceptChannelId)
        )
      )
  ).map(({ id }) => id);

  if (publicChannelIds.length === 0) {
    return [];
  }

  const [openRoles, audiencesBefore] = await Promise.all([
    db
      .select({ id: roles.id })
      .from(roles)
      .where(and(eq(roles.isDefault, false), ne(roles.id, OWNER_ROLE_ID))),
    Promise.all(
      publicChannelIds.map((channelId) =>
        getAffectedOnlineUserIdsForChannel(
          channelId,
          ChannelPermission.VIEW_CHANNEL
        )
      )
    )
  ]);

  const now = Date.now();
  const grants = publicChannelIds.flatMap((channelId) =>
    openRoles.flatMap(({ id: roleId }) =>
      Object.values(ChannelPermission).map((permission) => ({
        channelId,
        roleId,
        permission,
        allow: true,
        createdAt: now
      }))
    )
  );

  db.transaction((tx) => {
    tx.update(channels)
      .set({ private: true })
      .where(inArray(channels.id, publicChannelIds))
      .run();

    if (grants.length > 0) {
      tx.insert(channelRolePermissions)
        .values(grants)
        .onConflictDoNothing()
        .run();
    }
  });

  for (const [index, channelId] of publicChannelIds.entries()) {
    publishChannel(channelId, 'update', true);
    await publishChannelAccessChange(channelId, audiencesBefore[index]!);

    enqueueActivityLog({
      type: ActivityLogType.UPDATED_CHANNEL,
      userId,
      details: { channelId, values: { private: true } }
    });
  }

  return publicChannelIds;
};

export {
  closeChannelsToDefaultRole,
  createChannel,
  deleteChannel,
  MAX_REORDERED_CHANNELS,
  reorderChannels,
  runBeforeChannelDeleteHook,
  updateChannel,
  zChannelName,
  zChannelTopic
};
export type { TCreateChannel, TUpdateChannel };
