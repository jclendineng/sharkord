import { ServerEvents } from '@sharkord/shared';
import { describe, expect, spyOn, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { users } from '../../db/schema';
import { pubsub } from '../../utils/pubsub';

describe('friends', () => {
  test('should send a request, list it on both sides and become friends once accepted', async () => {
    const { caller: asker } = await initTest(1);
    const { caller: asked } = await initTest(2);

    await asker.friends.request({ userId: 2 });

    expect(await asker.friends.get()).toEqual({
      friends: [],
      incoming: [],
      outgoing: [2]
    });
    expect(await asked.friends.get()).toEqual({
      friends: [],
      incoming: [1],
      outgoing: []
    });

    await asked.friends.accept({ userId: 1 });

    expect((await asker.friends.get()).friends).toEqual([2]);
    expect((await asked.friends.get()).friends).toEqual([1]);
  });

  test('should make two people friends when both ask', async () => {
    const { caller: one } = await initTest(1);
    const { caller: two } = await initTest(2);

    await one.friends.request({ userId: 2 });
    await two.friends.request({ userId: 1 });

    expect((await one.friends.get()).friends).toEqual([2]);
  });

  test('should change nothing when the same request is sent twice', async () => {
    const { caller } = await initTest(1);

    await caller.friends.request({ userId: 2 });
    await caller.friends.request({ userId: 2 });

    expect((await caller.friends.get()).outgoing).toEqual([2]);
  });

  test('should tell both people when a friendship changes', async () => {
    const publish = spyOn(pubsub, 'publishFor');
    const { caller } = await initTest(1);

    await caller.friends.request({ userId: 2 });

    const calls = publish.mock.calls.filter(
      ([, event]) => event === ServerEvents.FRIENDSHIP_UPDATE
    );

    expect(calls.map(([userId]) => userId).sort()).toEqual([1, 2]);
  });

  test('should unfriend, cancel and decline through remove', async () => {
    const { caller: one } = await initTest(1);
    const { caller: two } = await initTest(2);

    await one.friends.request({ userId: 2 });
    await two.friends.remove({ userId: 1 });

    expect(await one.friends.get()).toEqual({
      friends: [],
      incoming: [],
      outgoing: []
    });

    await one.friends.request({ userId: 2 });
    await two.friends.accept({ userId: 1 });
    await one.friends.remove({ userId: 2 });

    expect((await two.friends.get()).friends).toEqual([]);
  });

  test('should refuse to accept a request that was never sent, or one you sent yourself', async () => {
    const { caller: one } = await initTest(1);

    await expect(one.friends.accept({ userId: 2 })).rejects.toThrow(
      'There is no friend request from them.'
    );

    await one.friends.request({ userId: 2 });

    await expect(one.friends.accept({ userId: 2 })).rejects.toThrow(
      'There is no friend request from them.'
    );
  });

  test('should refuse asking yourself, someone unknown, a banned user, or a friend again', async () => {
    const { caller: one } = await initTest(1);
    const { caller: two } = await initTest(2);

    await expect(one.friends.request({ userId: 1 })).rejects.toThrow(
      "You can't add yourself as a friend."
    );
    await expect(one.friends.request({ userId: 999 })).rejects.toThrow(
      'User not found'
    );

    await tdb.update(users).set({ banned: true }).where(eq(users.id, 3));

    await expect(one.friends.request({ userId: 3 })).rejects.toThrow(
      'User not found'
    );

    await one.friends.request({ userId: 2 });
    await two.friends.accept({ userId: 1 });

    await expect(one.friends.request({ userId: 2 })).rejects.toThrow(
      "You're already friends."
    );
  });

  test('should refuse removing someone who is not a friend', async () => {
    const { caller } = await initTest(1);

    await expect(caller.friends.remove({ userId: 2 })).rejects.toThrow(
      "You're not friends."
    );
  });
});
