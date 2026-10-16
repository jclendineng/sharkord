import { describe, expect, test } from 'bun:test';
import { eq, inArray } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { channels, messages } from '../../db/schema';
import { deleteExpiredMessages } from '../message-retention';

// seeded General (1) holds one message from setup time, these add older ones around it
const CHANNEL_ID = 1;
const DAY_MS = 24 * 60 * 60 * 1000;

const addMessage = async (
  daysAgo: number,
  extra: { pinned?: boolean; parentMessageId?: number } = {}
) => {
  const row = await tdb
    .insert(messages)
    .values({
      channelId: CHANNEL_ID,
      userId: 1,
      content: `<p>${daysAgo} days ago</p>`,
      createdAt: Date.now() - daysAgo * DAY_MS,
      ...extra
    })
    .returning({ id: messages.id })
    .get();

  return row.id;
};

const remainingIds = async (ids: number[]) => {
  const rows = await tdb
    .select({ id: messages.id })
    .from(messages)
    .where(inArray(messages.id, ids));

  return rows.map(({ id }) => id).sort((a, b) => a - b);
};

describe('message retention', () => {
  test('should delete old messages but keep pinned and recent ones', async () => {
    const old = await addMessage(40);
    const pinned = await addMessage(40, { pinned: true });
    const recent = await addMessage(5);

    await tdb
      .update(channels)
      .set({ retentionDays: 30 })
      .where(eq(channels.id, CHANNEL_ID));

    await deleteExpiredMessages();

    expect(await remainingIds([old, pinned, recent])).toEqual(
      [pinned, recent].sort((a, b) => a - b)
    );
  });

  test('should keep an old thread start while its thread is still going', async () => {
    const liveParent = await addMessage(40);
    const liveReply = await addMessage(2, { parentMessageId: liveParent });
    const deadParent = await addMessage(40);
    const deadReply = await addMessage(39, { parentMessageId: deadParent });

    await tdb
      .update(channels)
      .set({ retentionDays: 30 })
      .where(eq(channels.id, CHANNEL_ID));

    await deleteExpiredMessages();

    expect(
      await remainingIds([liveParent, liveReply, deadParent, deadReply])
    ).toEqual([liveParent, liveReply].sort((a, b) => a - b));
  });

  test('should leave a channel without retention alone', async () => {
    const old = await addMessage(400);

    await deleteExpiredMessages();

    expect(await remainingIds([old])).toEqual([old]);
  });

  test('should preview how many messages a period would delete', async () => {
    await addMessage(40);
    await addMessage(40, { pinned: true });
    await addMessage(5);

    const { caller } = await initTest(1);

    expect(
      await caller.channels.getRetentionPreview({
        channelId: CHANNEL_ID,
        retentionDays: 30
      })
    ).toBe(1);
  });

  test('should save retention on the channel and refuse a bad period', async () => {
    const { caller } = await initTest(1);

    await caller.channels.update({ channelId: CHANNEL_ID, retentionDays: 90 });

    const channel = await tdb
      .select({ retentionDays: channels.retentionDays })
      .from(channels)
      .where(eq(channels.id, CHANNEL_ID))
      .get();

    expect(channel?.retentionDays).toBe(90);
    await expect(
      caller.channels.update({ channelId: CHANNEL_ID, retentionDays: 0 })
    ).rejects.toThrow();
  });

  test('should refuse someone without MANAGE_CHANNELS', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.channels.getRetentionPreview({
        channelId: CHANNEL_ID,
        retentionDays: 30
      })
    ).rejects.toThrow('Insufficient permissions');
    await expect(
      caller.channels.update({ channelId: CHANNEL_ID, retentionDays: 30 })
    ).rejects.toThrow('Insufficient permissions');
  });
});
