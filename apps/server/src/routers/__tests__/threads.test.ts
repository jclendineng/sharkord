import { ChannelPermission } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';
import { initTest, sendMessage } from '../../__tests__/helpers';
import { config } from '../../config';

describe('messages.getThreads', () => {
  test("should list a channel's threads, the one replied to last first", async () => {
    const { caller } = await initTest();

    const olderId = await sendMessage(caller, {
      channelId: 1,
      content: 'Older thread',
      files: []
    });

    const newerId = await sendMessage(caller, {
      channelId: 1,
      content: 'Newer thread',
      files: []
    });

    await caller.messages.send({
      channelId: 1,
      content: 'Reply to newer',
      files: [],
      parentMessageId: newerId
    });

    await caller.messages.send({
      channelId: 1,
      content: 'First reply to older',
      files: [],
      parentMessageId: olderId
    });

    await caller.messages.send({
      channelId: 1,
      content: 'Second reply to older',
      files: [],
      parentMessageId: olderId
    });

    const threads = await caller.messages.getThreads({ channelId: 1 });

    expect(threads.map((thread) => thread.id)).toEqual([olderId, newerId]);
    expect(threads[0]!.content).toBe('Older thread');
    expect(threads[0]!.replyCount).toBe(2);
    expect(threads[1]!.replyCount).toBe(1);
    expect(threads[0]!.lastReplyAt).toBeGreaterThanOrEqual(
      threads[1]!.lastReplyAt
    );
  });

  test('should leave out messages without replies', async () => {
    const { caller } = await initTest();

    await sendMessage(caller, {
      channelId: 1,
      content: 'No replies here',
      files: []
    });

    const threads = await caller.messages.getThreads({ channelId: 1 });

    expect(threads).toEqual([]);
  });

  test('should throw for a direct message the caller is not in', async () => {
    const { caller } = await initTest(1);

    await expect(caller.messages.getThreads({ channelId: 3 })).rejects.toThrow(
      'You are not a participant in this DM channel'
    );
  });

  test('should throw when user lacks channel permissions', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    await caller1.channels.update({
      channelId: 1,
      name: 'General',
      topic: 'General text channel',
      private: true
    });

    await caller1.channels.updatePermissions({
      channelId: 1,
      roleId: 2,
      permissions: [ChannelPermission.SEND_MESSAGES]
    });

    await expect(caller2.messages.getThreads({ channelId: 1 })).rejects.toThrow(
      'Insufficient channel permissions'
    );
  });

  test('should reject a channel id that is not positive', async () => {
    const { caller } = await initTest();

    await expect(
      caller.messages.getThreads({ channelId: 0 })
    ).rejects.toThrow();
  });

  test('should rate limit excessive thread list fetches', async () => {
    const { caller } = await initTest();
    const { maxRequests } = config.rateLimiters.getMessages;

    for (let i = 0; i < maxRequests; i++) {
      await caller.messages.getThreads({ channelId: 1 });
    }

    await expect(caller.messages.getThreads({ channelId: 1 })).rejects.toThrow(
      'Too many requests'
    );
  });
});
