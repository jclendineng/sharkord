import { afterAll, beforeEach, describe, expect, spyOn, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { config } from '../../config';
import { getSettings } from '../../db/queries/server';
import { pushDevices, users } from '../../db/schema';
import { drainPushNotificationsQueue } from '../../queues/push-notifications';
import * as apns from '../../utils/apns';

/**
 * APNs itself is not reached: the harness has no network to apple and no key to sign with,
 * so sendApnsNotification is spied and everything that decides who it is called for is
 * covered here instead.
 */

const deviceToken = (userId: number) => `${userId}`.padStart(64, 'a');

const originalPushConfig = { ...config.push };

afterAll(() => {
  Object.assign(config.push, originalPushConfig);
});

beforeEach(() => {
  config.push.enabled = true;
});

const spyOnApns = (status = 200, reason?: string) =>
  spyOn(apns, 'sendApnsNotification').mockResolvedValue({ status, reason });

const registerDevices = async (...userIds: number[]) => {
  for (const userId of userIds) {
    const { caller } = await initTest(userId);

    await caller.notifications.registerDevice({
      token: deviceToken(userId),
      sandbox: false
    });
  }
};

const notifiedTokens = (spy: ReturnType<typeof spyOnApns>) =>
  spy.mock.calls.map(([notification]) => notification.deviceToken).sort();

describe('notifications.registerDevice', () => {
  test('should store the device against the caller and their session', async () => {
    const { caller } = await initTest(2);

    await caller.notifications.registerDevice({
      token: deviceToken(2).toUpperCase(),
      sandbox: true
    });

    const device = await tdb
      .select()
      .from(pushDevices)
      .where(eq(pushDevices.token, deviceToken(2)))
      .get();

    expect(device?.userId).toBe(2);
    expect(device?.sandbox).toBe(true);
    expect(device?.tokenVersion).toBe(0);
  });

  test('should move a token to the account that registered it last', async () => {
    const { caller: first } = await initTest(1);
    const { caller: second } = await initTest(2);

    await first.notifications.registerDevice({
      token: deviceToken(9),
      sandbox: false
    });
    await second.notifications.registerDevice({
      token: deviceToken(9),
      sandbox: false
    });

    const devices = await tdb.select().from(pushDevices);

    expect(devices).toHaveLength(1);
    expect(devices[0]!.userId).toBe(2);
  });

  test('should refuse when push is not enabled on the server', async () => {
    config.push.enabled = false;

    const { caller } = await initTest(2);

    await expect(
      caller.notifications.registerDevice({
        token: deviceToken(2),
        sandbox: false
      })
    ).rejects.toThrow('Push notifications are not enabled on this server.');
  });

  test('should refuse a token that is not hex', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.notifications.registerDevice({
        token: 'not-a-device-token',
        sandbox: false
      })
    ).rejects.toThrow();

    expect(await tdb.select().from(pushDevices)).toHaveLength(0);
  });
});

describe('notifications.unregisterDevice', () => {
  test("should remove the caller's own device", async () => {
    await registerDevices(2);

    const { caller } = await initTest(2);

    await caller.notifications.unregisterDevice({ token: deviceToken(2) });

    expect(await tdb.select().from(pushDevices)).toHaveLength(0);
  });

  test("should leave someone else's device alone", async () => {
    await registerDevices(3);

    const { caller } = await initTest(2);

    await caller.notifications.unregisterDevice({ token: deviceToken(3) });

    expect(await tdb.select().from(pushDevices)).toHaveLength(1);
  });
});

describe('push notifications for new messages', () => {
  test('should notify the other side of a direct message', async () => {
    await registerDevices(3, 4);

    const spy = spyOnApns();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(notifiedTokens(spy)).toEqual([deviceToken(4)]);

    const [[notification]] = spy.mock.calls as unknown as [
      [apns.TApnsNotification]
    ];

    const { serverId } = await getSettings();

    expect(notification.payload).toMatchObject({
      aps: { alert: { title: 'User A', body: 'hey b' } },
      serverId,
      channelId: 3
    });
  });

  test('should notify a mentioned user and nobody else in a channel', async () => {
    await registerDevices(2, 3);

    const spy = spyOnApns();
    const { caller } = await initTest(1);

    await caller.messages.send({
      channelId: 1,
      content:
        '<p><span data-type="mention" data-user-id="2" class="mention">@Test User</span> look</p>',
      files: []
    });
    await drainPushNotificationsQueue();

    expect(notifiedTokens(spy)).toEqual([deviceToken(2)]);

    const [[notification]] = spy.mock.calls as unknown as [
      [apns.TApnsNotification]
    ];

    expect(notification.payload).toMatchObject({
      aps: { alert: { title: 'Test Owner in #General' } }
    });
  });

  test('should notify everyone holding a mentioned role', async () => {
    await registerDevices(2, 3, 5);

    const spy = spyOnApns();
    const { caller } = await initTest(1);

    await caller.messages.send({
      channelId: 1,
      content:
        '<p><span data-type="role-mention" data-role-id="2" class="role-mention">@Member</span></p>',
      files: []
    });
    await drainPushNotificationsQueue();

    expect(notifiedTokens(spy)).toEqual([deviceToken(2), deviceToken(3)]);
  });

  test('should notify the author of the message being replied to', async () => {
    await registerDevices(1);

    const spy = spyOnApns();
    const { caller } = await initTest(2);

    await caller.messages.send({
      channelId: 1,
      content: 'replying',
      replyToMessageId: 1,
      files: []
    });
    await drainPushNotificationsQueue();

    expect(notifiedTokens(spy)).toEqual([deviceToken(1)]);
  });

  test('should not notify the sender about their own message', async () => {
    await registerDevices(1);

    const spy = spyOnApns();
    const { caller } = await initTest(1);

    await caller.messages.send({
      channelId: 1,
      content:
        '<p><span data-type="mention" data-user-id="1" class="mention">@Test Owner</span></p>',
      files: []
    });
    await drainPushNotificationsQueue();

    expect(spy).not.toHaveBeenCalled();
  });

  // channel 5 grants the default role view access and denies user 2 specifically
  test('should not notify a mentioned user who cannot see the channel', async () => {
    await registerDevices(2, 3);

    const spy = spyOnApns();
    const { caller } = await initTest(1);

    await caller.messages.send({
      channelId: 5,
      content:
        '<p><span data-type="mention" data-user-id="2" class="mention">@Test User</span><span data-type="mention" data-user-id="3" class="mention">@User A</span></p>',
      files: []
    });
    await drainPushNotificationsQueue();

    expect(notifiedTokens(spy)).toEqual([deviceToken(3)]);
  });

  test("should stop notifying a device once the user's sessions are ended", async () => {
    await registerDevices(4);

    await tdb.update(users).set({ tokenVersion: 1 }).where(eq(users.id, 4));

    const spy = spyOnApns();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(spy).not.toHaveBeenCalled();
  });

  test('should not notify a banned user', async () => {
    await registerDevices(4);

    await tdb.update(users).set({ banned: true }).where(eq(users.id, 4));

    const spy = spyOnApns();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(spy).not.toHaveBeenCalled();
  });

  test('should forget a device apns says is gone', async () => {
    await registerDevices(4);

    spyOnApns(410, 'Unregistered');

    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(await tdb.select().from(pushDevices)).toHaveLength(0);
  });

  test('should keep a device apns refused for another reason', async () => {
    await registerDevices(4);

    spyOnApns(429, 'TooManyRequests');

    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(await tdb.select().from(pushDevices)).toHaveLength(1);
  });

  test('should send nothing while push is disabled', async () => {
    await registerDevices(4);

    config.push.enabled = false;

    const spy = spyOnApns();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(spy).not.toHaveBeenCalled();
  });
});

describe('channel notification settings', () => {
  const MENTION_USER_2 =
    '<p><span data-type="mention" data-user-id="2" class="mention">@Test User</span> look</p>';

  test('should store a channel setting and forget it when set back to the default', async () => {
    const { caller } = await initTest(2);

    await caller.notifications.setChannelSetting({
      channelId: 1,
      level: 'all'
    });

    expect(await caller.notifications.getChannelSettings()).toEqual([
      { channelId: 1, level: 'all' }
    ]);

    await caller.notifications.setChannelSetting({
      channelId: 1,
      level: 'none'
    });

    expect(await caller.notifications.getChannelSettings()).toEqual([
      { channelId: 1, level: 'none' }
    ]);

    await caller.notifications.setChannelSetting({
      channelId: 1,
      level: 'mentions'
    });

    expect(await caller.notifications.getChannelSettings()).toEqual([]);
  });

  test("should only list the caller's own settings", async () => {
    const { caller: owner } = await initTest(1);
    const { caller: member } = await initTest(2);

    await owner.notifications.setChannelSetting({
      channelId: 1,
      level: 'none'
    });

    expect(await member.notifications.getChannelSettings()).toEqual([]);
  });

  test('should refuse a channel the caller cannot see', async () => {
    const { caller } = await initTest(2);

    // user 2 is denied viewing channel 5
    await expect(
      caller.notifications.setChannelSetting({ channelId: 5, level: 'all' })
    ).rejects.toThrow('Insufficient channel permissions');
  });

  test('should refuse an unknown level', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.notifications.setChannelSetting({
        channelId: 1,
        // @ts-expect-error not one of the levels
        level: 'loud'
      })
    ).rejects.toThrow();
  });

  test('should push every message in a channel set to all', async () => {
    await registerDevices(2, 3);

    const { caller: member } = await initTest(2);

    await member.notifications.setChannelSetting({
      channelId: 1,
      level: 'all'
    });

    const spy = spyOnApns();
    const { caller } = await initTest(1);

    await caller.messages.send({
      channelId: 1,
      content: '<p>nothing special</p>',
      files: []
    });
    await drainPushNotificationsQueue();

    expect(notifiedTokens(spy)).toEqual([deviceToken(2)]);
  });

  test('should push nothing from a muted channel, mentions included', async () => {
    await registerDevices(2);

    const { caller: member } = await initTest(2);

    await member.notifications.setChannelSetting({
      channelId: 1,
      level: 'none'
    });

    const spy = spyOnApns();
    const { caller } = await initTest(1);

    await caller.messages.send({
      channelId: 1,
      content: MENTION_USER_2,
      files: []
    });
    await drainPushNotificationsQueue();

    expect(notifiedTokens(spy)).toEqual([]);
  });

  test('should push nothing from a muted direct message', async () => {
    await registerDevices(4);

    const { caller: userB } = await initTest(4);

    await userB.notifications.setChannelSetting({
      channelId: 3,
      level: 'none'
    });

    const spy = spyOnApns();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(notifiedTokens(spy)).toEqual([]);
  });
});
