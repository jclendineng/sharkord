import {
  ActivityLogType,
  IP_BANNED_MESSAGE,
  ServerEvents,
  zLocale
} from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import {
  getAllChannelUserPermissions,
  getChannelsForUser,
  getChannelsReadStatesForUser
} from '../../db/queries/channels';
import { getEmojis } from '../../db/queries/emojis';
import { isIpBanned } from '../../db/queries/ip-bans';
import { hasUserJoinedBefore } from '../../db/queries/logins';
import { getRoles } from '../../db/queries/roles';
import { getPublicSettings, getSettings } from '../../db/queries/server';
import { getSounds } from '../../db/queries/soundboard-sounds';
import { getStickers } from '../../db/queries/stickers';
import { getPublicUsers } from '../../db/queries/users';
import { categories, users } from '../../db/schema';
import { getCapabilityAccessRules } from '../../helpers/plugin-capability-access';
import { safeCompare } from '../../helpers/safe-compare';
import { shouldAskServerPassword } from '../../helpers/should-ask-server-password';
import { logger } from '../../logger';
import { pluginManager } from '../../plugins';
import { eventBus } from '../../plugins/event-bus';
import { enqueueActivityLog } from '../../queues/activity-log';
import { enqueueLogin } from '../../queues/logins';
import { VoiceRuntime } from '../../runtimes/voice';
import { SERVER_VERSION } from '../../utils/env';
import { invariant } from '../../utils/invariant';
import {
  createRateLimiter,
  getClientRateLimitKey
} from '../../utils/rate-limiters/rate-limiter';
import { publicProcedure } from '../../utils/trpc';
import { setUserPresence } from '../../utils/wss';

// only joins that check the server password count, since that is where guessing happens. a
// refresh joins again with a session already good, and counting those signed people out after a
// few refreshes. how often anyone joins at all stays bounded by the handshake each join needs
const passwordAttemptLimiter = createRateLimiter({
  maxRequests: config.rateLimiters.joinServer.maxRequests,
  windowMs: config.rateLimiters.joinServer.windowMs
});

const joinServerRoute = publicProcedure
  .input(
    z.object({
      handshakeHash: z.string(),
      password: z.string().optional(),
      locale: zLocale.optional()
    })
  )
  .query(async ({ input, ctx }) => {
    invariant(ctx.user, {
      code: 'UNAUTHORIZED',
      message: 'User not authenticated'
    });

    const connectionInfo = ctx.getConnectionInfo();
    const [settings, isBannedNetwork] = await Promise.all([
      getSettings(),
      isIpBanned(connectionInfo?.ip)
    ]);

    // an account signed in elsewhere still cannot use the server from a banned network
    invariant(!isBannedNetwork, {
      code: 'FORBIDDEN',
      message: IP_BANNED_MESSAGE
    });

    const shouldAskForPassword = await shouldAskServerPassword(ctx.user.id, {
      password: settings.password,
      onlyAskForPasswordOnFirstJoin: settings.onlyAskForPasswordOnFirstJoin
    });

    if (shouldAskForPassword) {
      const { allowed } = passwordAttemptLimiter.consume(
        getClientRateLimitKey(`user:${ctx.user.id}`)
      );

      invariant(allowed, {
        code: 'TOO_MANY_REQUESTS',
        message: 'Too many requests. Please try again shortly.'
      });
    }

    invariant(
      input.handshakeHash &&
        ctx.handshakeHash &&
        input.handshakeHash === ctx.handshakeHash,
      {
        code: 'FORBIDDEN',
        message: 'Invalid handshake hash'
      }
    );

    // constant time, so the response cannot be used to learn the password a character at a
    // time. the column is still plaintext, which is the open half of 4.8
    const passwordMatches =
      !!settings.password &&
      !!input.password &&
      safeCompare(input.password, settings.password);

    invariant(shouldAskForPassword ? passwordMatches : true, {
      code: 'FORBIDDEN',
      message: 'Invalid password'
    });

    ctx.authenticated = true;
    ctx.setWsUserId(ctx.user.id);
    setUserPresence(ctx.user.id, ctx.user.presence);

    if (input.locale) ctx.locale = input.locale;

    const [
      allCategories,
      channelsForUser,
      publicUsers,
      roles,
      emojis,
      channelPermissions,
      readStates,
      publicSettings,
      pluginsMetadata,
      hasJoinedBefore,
      pluginCapabilityAccess,
      stickers,
      sounds
    ] = await Promise.all([
      db.select().from(categories),
      getChannelsForUser(ctx.user.id), // filter channels based on permissions and DM participation
      getPublicUsers(true), // return identity to get status of already connected users
      getRoles(),
      getEmojis(),
      getAllChannelUserPermissions(ctx.user.id),
      getChannelsReadStatesForUser(ctx.user.id),
      getPublicSettings(),
      pluginManager.getActivePluginMetadata(),
      hasUserJoinedBefore(ctx.user.id),
      getCapabilityAccessRules(),
      getStickers(),
      getSounds()
    ]);

    const showWelcomeDialog = settings.showWelcomeDialog && !hasJoinedBefore;

    const processedPublicUsers = publicUsers.map((u) => ({
      ...u,
      status: ctx.getStatusById(u.id),
      _identity: undefined // remove identity before sending to client
    }));

    const foundPublicUser = processedPublicUsers.find(
      (u) => u.id === ctx.user.id
    );

    invariant(foundPublicUser, {
      code: 'NOT_FOUND',
      message: 'User not present in public users'
    });

    logger.info('%s joined the server', ctx.user.name);

    ctx.pubsub.publish(ServerEvents.USER_JOIN, {
      ...foundPublicUser,
      status: ctx.getStatusById(ctx.user.id)
    });

    if (connectionInfo?.ip) {
      ctx.saveUserIp(ctx.user.id, connectionInfo.ip);
    }

    // who is in a voice channel is only for the people who can see it
    const visibleChannelIds = new Set(
      channelsForUser.map((channel) => channel.id)
    );
    const voiceMap = Object.fromEntries(
      Object.entries(VoiceRuntime.getVoiceMap()).filter(([channelId]) =>
        visibleChannelIds.has(Number(channelId))
      )
    );
    const externalStreamsMap = Object.fromEntries(
      Object.entries(VoiceRuntime.getExternalStreamsMap()).filter(
        ([channelId]) => visibleChannelIds.has(Number(channelId))
      )
    );

    await db
      .update(users)
      .set({ lastLoginAt: Date.now() })
      .where(eq(users.id, ctx.user.id));

    enqueueLogin(ctx.user.id, connectionInfo, ctx.sessionId);
    enqueueActivityLog({
      type: ActivityLogType.USER_JOINED,
      userId: ctx.user.id,
      ip: connectionInfo?.ip
    });

    eventBus.emit('user:joined', {
      userId: ctx.user.id,
      username: ctx.user.name
    });

    return {
      categories: allCategories,
      channels: channelsForUser,
      users: processedPublicUsers,
      serverId: settings.serverId,
      serverName: settings.name,
      // for the apps' about page. only once signed in, /info keeps it from strangers
      serverVersion: SERVER_VERSION,
      ownUserId: ctx.user.id,
      ownUserPasswordSet: ctx.user.passwordSet,
      voiceMap,
      roles,
      emojis,
      stickers,
      sounds,
      publicSettings,
      channelPermissions,
      readStates,
      commands: pluginManager.getCommands(),
      pluginIdsWithComponents: pluginManager.getPluginIdsWithComponents(),
      pluginCapabilityAccess,
      pluginsMetadata,
      externalStreamsMap,
      showWelcomeDialog
    };
  });

export { joinServerRoute };
