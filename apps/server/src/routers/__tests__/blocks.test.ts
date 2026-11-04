import { ServerEvents } from '@sharkord/shared';
import { describe, expect, spyOn, test } from 'bun:test';
import { initTest } from '../../__tests__/helpers';
import { pubsub } from '../../utils/pubsub';

describe('blocks', () => {
  test('should list a blocked user and drop them again once unblocked', async () => {
    const { caller } = await initTest(1);

    await caller.friends.block({ userId: 2 });

    expect((await caller.friends.get()).blocked).toEqual([2]);

    await caller.friends.unblock({ userId: 2 });

    expect((await caller.friends.get()).blocked).toEqual([]);
  });

  test('should change nothing when the same user is blocked twice', async () => {
    const { caller } = await initTest(1);

    await caller.friends.block({ userId: 2 });
    await caller.friends.block({ userId: 2 });

    expect((await caller.friends.get()).blocked).toEqual([2]);
  });

  test('should only show the block to the user who made it', async () => {
    const { caller: blocker } = await initTest(1);
    const { caller: blocked } = await initTest(2);

    await blocker.friends.block({ userId: 2 });

    expect((await blocked.friends.get()).blocked).toEqual([]);
  });

  test('should end a friendship and a pending request either way', async () => {
    const { caller: one } = await initTest(1);
    const { caller: two } = await initTest(2);
    const { caller: three } = await initTest(3);

    await one.friends.request({ userId: 2 });
    await two.friends.accept({ userId: 1 });
    await three.friends.request({ userId: 1 });

    await one.friends.block({ userId: 2 });
    await one.friends.block({ userId: 3 });

    expect(await one.friends.get()).toEqual({
      friends: [],
      incoming: [],
      outgoing: [],
      blocked: [2, 3]
    });
    expect((await two.friends.get()).friends).toEqual([]);
    expect((await three.friends.get()).outgoing).toEqual([]);
  });

  test('should tell the blocked user only when a friendship ended', async () => {
    const publish = spyOn(pubsub, 'publishFor');
    const { caller: one } = await initTest(1);
    const { caller: two } = await initTest(2);

    await one.friends.block({ userId: 3 });

    const strangerCalls = publish.mock.calls.filter(
      ([, event]) => event === ServerEvents.FRIENDSHIP_UPDATE
    );

    expect(strangerCalls.map(([userId]) => userId)).toEqual([1]);

    await one.friends.request({ userId: 2 });
    await two.friends.accept({ userId: 1 });

    publish.mockClear();

    await one.friends.block({ userId: 2 });

    const friendCalls = publish.mock.calls.filter(
      ([, event]) => event === ServerEvents.FRIENDSHIP_UPDATE
    );

    expect(friendCalls.map(([userId]) => userId).sort()).toEqual([1, 2]);
  });

  test('should tell only the blocker when they unblock', async () => {
    const { caller } = await initTest(1);

    await caller.friends.block({ userId: 2 });

    const publish = spyOn(pubsub, 'publishFor');

    await caller.friends.unblock({ userId: 2 });

    const calls = publish.mock.calls.filter(
      ([, event]) => event === ServerEvents.FRIENDSHIP_UPDATE
    );

    expect(calls.map(([userId]) => userId)).toEqual([1]);
  });

  test('should refuse blocking yourself or someone unknown', async () => {
    const { caller } = await initTest(1);

    await expect(caller.friends.block({ userId: 1 })).rejects.toThrow(
      "You can't block yourself."
    );
    await expect(caller.friends.block({ userId: 999 })).rejects.toThrow(
      'User not found'
    );
  });

  test('should refuse an id that is not a positive whole number', async () => {
    const { caller } = await initTest(1);

    await expect(caller.friends.block({ userId: 0 })).rejects.toThrow();
    await expect(caller.friends.unblock({ userId: -1 })).rejects.toThrow();
  });

  test('should refuse unblocking someone who is not blocked', async () => {
    const { caller } = await initTest(2);

    await expect(caller.friends.unblock({ userId: 1 })).rejects.toThrow(
      "You haven't blocked this person."
    );
  });

  test('should refuse friend requests across a block, either way', async () => {
    const { caller: blocker } = await initTest(1);
    const { caller: blocked } = await initTest(2);

    await blocker.friends.block({ userId: 2 });

    await expect(blocker.friends.request({ userId: 2 })).rejects.toThrow(
      'You blocked this person. Unblock them to send a friend request.'
    );
    await expect(blocked.friends.request({ userId: 1 })).rejects.toThrow(
      "That friend request couldn't be sent."
    );
  });

  test('should refuse a new direct message across a block, either way', async () => {
    const { caller: blocker } = await initTest(1);
    const { caller: blocked } = await initTest(2);

    await blocker.friends.block({ userId: 2 });

    await expect(blocker.dms.open({ userId: 2 })).rejects.toThrow(
      'You blocked this person. Unblock them to message them.'
    );
    await expect(blocked.dms.open({ userId: 1 })).rejects.toThrow(
      "This person isn't accepting direct messages."
    );
  });

  test('should still open a direct message that existed before the block', async () => {
    const { caller } = await initTest(3);

    await caller.friends.block({ userId: 4 });

    // channel 3 is the seeded conversation between users 3 and 4
    expect(await caller.dms.open({ userId: 4 })).toEqual({ channelId: 3 });
  });

  test('should refuse sending in a direct message across a block, either way', async () => {
    const { caller: blocker } = await initTest(3);
    const { caller: blocked } = await initTest(4);

    await blocker.friends.block({ userId: 4 });

    await expect(
      blocker.messages.send({ channelId: 3, content: 'hello', files: [] })
    ).rejects.toThrow(
      'You blocked this person. Unblock them to send a message.'
    );
    await expect(
      blocked.messages.send({ channelId: 3, content: 'hello', files: [] })
    ).rejects.toThrow("Your message couldn't be delivered.");
  });

  test('should send in the direct message again once unblocked', async () => {
    const { caller } = await initTest(3);

    await caller.friends.block({ userId: 4 });
    await caller.friends.unblock({ userId: 4 });

    await caller.messages.send({ channelId: 3, content: 'hello', files: [] });

    const { messages } = await caller.messages.get({
      channelId: 3,
      cursor: null,
      limit: 50
    });

    expect(messages[0]!.content).toBe('hello');
  });

  test('should leave messages in server channels alone', async () => {
    const { caller: blocker } = await initTest(1);
    const { caller: blocked } = await initTest(2);

    await blocker.friends.block({ userId: 2 });

    await blocked.messages.send({
      channelId: 1,
      content: 'still here',
      files: []
    });

    const { messages } = await blocker.messages.get({
      channelId: 1,
      cursor: null,
      limit: 50
    });

    expect(messages[0]!.content).toBe('still here');
  });
});
