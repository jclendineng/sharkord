import { getErrorMessage } from '@sharkord/shared';
import chalk from 'chalk';
import {
  and,
  count,
  eq,
  gte,
  inArray,
  isNotNull,
  lt,
  notExists,
  sql
} from 'drizzle-orm';
import { alias } from 'drizzle-orm/sqlite-core';
import { db } from '../db';
import { channels, messages } from '../db/schema';
import { logger } from '../logger';

const DAY_MS = 24 * 60 * 60 * 1000;

// small batches keep each delete short, sqlite runs in the server's own process
const RETENTION_BATCH_SIZE = 500;

const replies = alias(messages, 'retention_replies');

// what a channel's retention deletes: older than the cutoff, not pinned, and not the start of a
// thread that is still going, since deleting a parent takes its replies with it
const expiredMessagesWhere = (channelId: number, cutoff: number) =>
  and(
    eq(messages.channelId, channelId),
    lt(messages.createdAt, cutoff),
    // pinned is nullable, and not(pinned = 1) is null rather than true for a null row
    sql`coalesce(${messages.pinned}, 0) = 0`,
    notExists(
      db
        .select({ one: sql`1` })
        .from(replies)
        .where(
          and(
            eq(replies.parentMessageId, messages.id),
            gte(replies.createdAt, cutoff)
          )
        )
    )
  );

const getRetentionCutoff = (retentionDays: number) =>
  Date.now() - retentionDays * DAY_MS;

// the dry run the settings screen shows before retention is saved
const countExpiredMessages = async (
  channelId: number,
  retentionDays: number
) => {
  const result = await db
    .select({ total: count() })
    .from(messages)
    .where(expiredMessagesWhere(channelId, getRetentionCutoff(retentionDays)))
    .get();

  return result?.total ?? 0;
};

const deleteExpiredMessagesInChannel = async (
  channelId: number,
  retentionDays: number
) => {
  const cutoff = getRetentionCutoff(retentionDays);
  let deleted = 0;

  for (;;) {
    const batch = await db
      .select({ id: messages.id })
      .from(messages)
      .where(expiredMessagesWhere(channelId, cutoff))
      .limit(RETENTION_BATCH_SIZE);

    if (batch.length === 0) break;

    await db.delete(messages).where(
      inArray(
        messages.id,
        batch.map(({ id }) => id)
      )
    );

    deleted += batch.length;

    if (batch.length < RETENTION_BATCH_SIZE) break;
  }

  return deleted;
};

// their files are left to the orphaned file sweep, which already removes files no message uses
const deleteExpiredMessages = async () => {
  const channelsWithRetention = await db
    .select({ id: channels.id, retentionDays: channels.retentionDays })
    .from(channels)
    .where(isNotNull(channels.retentionDays));

  for (const { id, retentionDays } of channelsWithRetention) {
    if (!retentionDays) continue;

    try {
      const deleted = await deleteExpiredMessagesInChannel(id, retentionDays);

      if (deleted > 0) {
        logger.info(
          `${chalk.dim('[Cron]')} Retention deleted ${deleted} message(s) in channel ${id}`
        );
      }
    } catch (error) {
      logger.error(
        `${chalk.dim('[Cron]')} Retention failed in channel ${id}: %s`,
        getErrorMessage(error)
      );
    }
  }
};

export { countExpiredMessages, deleteExpiredMessages };
