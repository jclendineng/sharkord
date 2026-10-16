import { ChannelType, getErrorMessage } from '@sharkord/shared';
import chalk from 'chalk';
import { eq, inArray } from 'drizzle-orm';
import { db } from '../db';
import { getSettings } from '../db/queries/server';
import { channels } from '../db/schema';
import { moveVoiceUser } from '../helpers/voice-moderation';
import { logger } from '../logger';
import { VoiceRuntime } from '../runtimes/voice';

// discord's afk channel: whoever has been silent in a call for the server's timeout is moved
// into it, through the same move a moderator makes. direct message calls are left alone
const moveAfkUsers = async () => {
  const { afkChannelId, afkTimeoutSeconds } = await getSettings();

  if (!afkChannelId) return;

  const runtimes = VoiceRuntime.getAll().filter(
    (runtime) => runtime.id !== afkChannelId
  );

  if (runtimes.length === 0) return;

  const [afkChannel, callChannels] = await Promise.all([
    db
      .select({ type: channels.type, isDm: channels.isDm })
      .from(channels)
      .where(eq(channels.id, afkChannelId))
      .limit(1)
      .get(),
    db
      .select({ id: channels.id, isDm: channels.isDm })
      .from(channels)
      .where(
        inArray(
          channels.id,
          runtimes.map((runtime) => runtime.id)
        )
      )
  ]);

  // a deleted or changed channel turns afk off rather than moving people somewhere odd
  if (!afkChannel || afkChannel.type !== ChannelType.VOICE || afkChannel.isDm) {
    return;
  }

  const dmChannelIds = new Set(
    callChannels.filter(({ isDm }) => isDm).map(({ id }) => id)
  );
  const idleMs = afkTimeoutSeconds * 1000;

  const moves = runtimes
    .filter((runtime) => !dmChannelIds.has(runtime.id))
    .flatMap((runtime) =>
      runtime.getIdleUserIds(idleMs).map(async (userId) => {
        // counted as active again, so a client slow to follow is not asked every tick
        runtime.markActive(userId);

        try {
          await moveVoiceUser(userId, afkChannelId);

          logger.debug(
            `${chalk.dim('[Cron]')} Moved user ${userId} to the afk channel`
          );
        } catch (error) {
          logger.debug(
            `${chalk.dim('[Cron]')} Could not move user ${userId} to the afk channel: %s`,
            getErrorMessage(error)
          );
        }
      })
    );

  await Promise.all(moves);
};

export { moveAfkUsers };
