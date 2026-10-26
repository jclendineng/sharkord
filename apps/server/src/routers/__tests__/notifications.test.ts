import { describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import {
  createPushKey,
  initTest,
  openPush,
  pushDeviceId,
  pushedPayload,
  pushedTickets,
  pushTicket,
  registerPushDevice,
  spyOnPushRelay,
  testPushKey
} from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { getSettings } from '../../db/queries/server';
import {
  channelNotificationSettings,
  pushDevices,
  users
} from '../../db/schema';
import { drainPushNotificationsQueue } from '../../queues/push-notifications';

/**
 * The push relay is not reached: the harness has no network to it, so sendRelayNotification
 * is spied and everything that decides who it is called for, and what they would read, is
 * covered here instead. its signed request is covered in utils/__tests__/push-relay.test.ts
 * and the relay itself in apps/push-relay.
 */

const registerDevices = async (...userIds: number[]) => {
  for (const userId of userIds) {
    await registerPushDevice(userId);
  }
};

const turnPushOff = async () => {
  const { caller } = await initTest(1);

  await caller.others.updateSettings({ pushRelayEnabled: false });
};

describe('notifications.registerDevice', () => {
  test('should store the ticket and key against the caller', async () => {
    await registerPushDevice(2);

    const device = await tdb
      .select()
      .from(pushDevices)
      .where(eq(pushDevices.token, pushDeviceId(2)))
      .get();

    expect(device?.userId).toBe(2);
    expect(device?.relayTicket).toBe(pushTicket(2));
    expect(device?.encryptionKey).toBe(testPushKey.encryptionKey);
    expect(device?.tokenVersion).toBe(0);
  });

  test('should replace the ticket when the app refreshes it', async () => {
    const { caller } = await initTest(2);

    await caller.notifications.registerDevice({
      token: pushDeviceId(2),
      relayTicket: 'first',
      encryptionKey: testPushKey.encryptionKey
    });
    await caller.notifications.registerDevice({
      token: pushDeviceId(2),
      relayTicket: 'second',
      encryptionKey: testPushKey.encryptionKey
    });

    const devices = await tdb.select().from(pushDevices);

    expect(devices).toHaveLength(1);
    expect(devices[0]!.relayTicket).toBe('second');
  });

  test('should move a device to the account that registered it last', async () => {
    const { caller: first } = await initTest(1);
    const { caller: second } = await initTest(2);

    for (const caller of [first, second]) {
      await caller.notifications.registerDevice({
        token: pushDeviceId(9),
        relayTicket: pushTicket(9),
        encryptionKey: testPushKey.encryptionKey
      });
    }

    const devices = await tdb.select().from(pushDevices);

    expect(devices).toHaveLength(1);
    expect(devices[0]!.userId).toBe(2);
  });

  test('should refuse a device while push is turned off', async () => {
    await turnPushOff();

    const { caller } = await initTest(2);

    await expect(
      caller.notifications.registerDevice({
        token: pushDeviceId(2),
        relayTicket: pushTicket(2),
        encryptionKey: testPushKey.encryptionKey
      })
    ).rejects.toThrow('Push notifications are not enabled on this server.');

    expect(await tdb.select().from(pushDevices)).toHaveLength(0);
  });

  test('should refuse a bare apns token, which the server can no longer push to', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.notifications.registerDevice({
        token: '2'.padStart(64, 'a'),
        // @ts-expect-error the shape a build from before the relay sent
        sandbox: false
      })
    ).rejects.toThrow();

    expect(await tdb.select().from(pushDevices)).toHaveLength(0);
  });

  test('should refuse an encryption key that is not a p-256 point', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.notifications.registerDevice({
        token: pushDeviceId(2),
        relayTicket: pushTicket(2),
        encryptionKey: 'A'.repeat(87)
      })
    ).rejects.toThrow('This device sent an encryption key that is not valid.');

    expect(await tdb.select().from(pushDevices)).toHaveLength(0);
  });

  test('should refuse a ticket with characters a ticket never has', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.notifications.registerDevice({
        token: pushDeviceId(2),
        relayTicket: 'not a ticket!',
        encryptionKey: testPushKey.encryptionKey
      })
    ).rejects.toThrow();

    expect(await tdb.select().from(pushDevices)).toHaveLength(0);
  });
});

describe('notifications.unregisterDevice', () => {
  test("should remove the caller's own device", async () => {
    await registerDevices(2);

    const { caller } = await initTest(2);

    await caller.notifications.unregisterDevice({ token: pushDeviceId(2) });

    expect(await tdb.select().from(pushDevices)).toHaveLength(0);
  });

  test("should leave someone else's device alone", async () => {
    await registerDevices(3);

    const { caller } = await initTest(2);

    await caller.notifications.unregisterDevice({ token: pushDeviceId(3) });

    expect(await tdb.select().from(pushDevices)).toHaveLength(1);
  });
});

describe('push notifications for new messages', () => {
  test('should notify the other side of a direct message', async () => {
    await registerDevices(3, 4);

    const spy = spyOnPushRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([pushTicket(4)]);

    const payload = await pushedPayload(spy);

    const { serverId } = await getSettings();

    expect(payload).toMatchObject({
      aps: { alert: { title: 'User A', body: 'hey b' } },
      serverId,
      channelId: 3
    });
  });

  test('should notify a mentioned user and nobody else in a channel', async () => {
    await registerDevices(2, 3);

    const spy = spyOnPushRelay();
    const { caller } = await initTest(1);

    await caller.messages.send({
      channelId: 1,
      content:
        '<p><span data-type="mention" data-user-id="2" class="mention">@Test User</span> look</p>',
      files: []
    });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([pushTicket(2)]);

    const payload = await pushedPayload(spy);

    expect(payload).toMatchObject({
      aps: { alert: { title: 'Test Owner in #General' } }
    });
  });

  test('should notify everyone holding a mentioned role', async () => {
    await registerDevices(2, 3, 5);

    const spy = spyOnPushRelay();
    const { caller } = await initTest(1);

    await caller.messages.send({
      channelId: 1,
      content:
        '<p><span data-type="role-mention" data-role-id="2" class="role-mention">@Member</span></p>',
      files: []
    });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([pushTicket(2), pushTicket(3)]);
  });

  test('should notify the author of the message being replied to', async () => {
    await registerDevices(1);

    const spy = spyOnPushRelay();
    const { caller } = await initTest(2);

    await caller.messages.send({
      channelId: 1,
      content: 'replying',
      replyToMessageId: 1,
      files: []
    });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([pushTicket(1)]);
  });

  test('should notify whoever started a thread about a reply in it', async () => {
    await registerDevices(1);

    const spy = spyOnPushRelay();
    const { caller } = await initTest(2);

    await caller.messages.send({
      channelId: 1,
      content: 'in the thread',
      parentMessageId: 1,
      files: []
    });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([pushTicket(1)]);

    const payload = await pushedPayload(spy);

    // what the app opens the thread from
    expect(payload).toMatchObject({ parentMessageId: 1 });
  });

  test('should keep each line of the message on its own line', async () => {
    await registerDevices(4);

    const spy = spyOnPushRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({
      channelId: 3,
      content: '<p>line one</p><p>line two</p>',
      files: []
    });
    await drainPushNotificationsQueue();

    const payload = await pushedPayload(spy);

    expect(payload).toMatchObject({
      aps: { alert: { body: 'line one\nline two' } }
    });
  });

  test('should not notify the sender about their own message', async () => {
    await registerDevices(1);

    const spy = spyOnPushRelay();
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

    const spy = spyOnPushRelay();
    const { caller } = await initTest(1);

    await caller.messages.send({
      channelId: 5,
      content:
        '<p><span data-type="mention" data-user-id="2" class="mention">@Test User</span><span data-type="mention" data-user-id="3" class="mention">@User A</span></p>',
      files: []
    });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([pushTicket(3)]);
  });

  test("should stop notifying a device once the user's sessions are ended", async () => {
    await registerDevices(4);

    await tdb.update(users).set({ tokenVersion: 1 }).where(eq(users.id, 4));

    const spy = spyOnPushRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(spy).not.toHaveBeenCalled();
  });

  test('should not notify a banned user', async () => {
    await registerDevices(4);

    await tdb.update(users).set({ banned: true }).where(eq(users.id, 4));

    const spy = spyOnPushRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(spy).not.toHaveBeenCalled();
  });

  test('should forget a device apple says is gone', async () => {
    await registerDevices(4);

    spyOnPushRelay(410, 'Unregistered');

    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(await tdb.select().from(pushDevices)).toHaveLength(0);
  });

  test('should keep a device apple refused for another reason', async () => {
    await registerDevices(4);

    spyOnPushRelay(429, 'TooManyRequests');

    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(await tdb.select().from(pushDevices)).toHaveLength(1);
  });

  test('should send nothing while push is turned off', async () => {
    await registerDevices(4);
    await turnPushOff();

    const spy = spyOnPushRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(spy).not.toHaveBeenCalled();
  });
});

describe('message previews in push', () => {
  test('should show the content by default', async () => {
    const { pushShowMessageContent } = await getSettings();

    expect(pushShowMessageContent).toBe(true);
  });

  test('should leave out the content of a direct message when previews are off', async () => {
    await registerDevices(4);

    const { caller: owner } = await initTest(1);

    await owner.others.updateSettings({ pushShowMessageContent: false });

    const spy = spyOnPushRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    const payload = await pushedPayload(spy);

    expect(payload).toMatchObject({
      aps: { alert: { title: 'User A', body: 'Sent you a direct message' } },
      channelId: 3
    });
    expect(JSON.stringify(payload)).not.toContain('hey b');
  });

  test('should leave out the content and the channel of a mention when previews are off', async () => {
    await registerDevices(2);

    const { caller } = await initTest(1);

    await caller.others.updateSettings({ pushShowMessageContent: false });

    const spy = spyOnPushRelay();

    await caller.messages.send({
      channelId: 1,
      content:
        '<p><span data-type="mention" data-user-id="2" class="mention">@Test User</span> secret plans</p>',
      files: []
    });
    await drainPushNotificationsQueue();

    const payload = await pushedPayload(spy);

    expect(payload).toMatchObject({
      aps: { alert: { title: 'Test Owner', body: 'Sent a message' } }
    });
    expect(JSON.stringify(payload)).not.toContain('secret plans');
    expect(JSON.stringify(payload)).not.toContain('General');
  });

  test('should refuse to change previews without permission to manage settings', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.others.updateSettings({ pushShowMessageContent: false })
    ).rejects.toThrow('Insufficient permissions');

    const { pushShowMessageContent } = await getSettings();

    expect(pushShowMessageContent).toBe(true);
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
      { channelId: 1, level: 'all', mutedUntil: null }
    ]);

    await caller.notifications.setChannelSetting({
      channelId: 1,
      level: 'none'
    });

    expect(await caller.notifications.getChannelSettings()).toEqual([
      { channelId: 1, level: 'none', mutedUntil: null }
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

  test('should keep a mute for a while and drop it once it runs out', async () => {
    const { caller } = await initTest(2);
    const before = Date.now();

    await caller.notifications.setChannelSetting({
      channelId: 1,
      level: 'none',
      muteForMinutes: 60
    });

    const [setting] = await caller.notifications.getChannelSettings();

    expect(setting!.level).toBe('none');
    expect(setting!.mutedUntil).toBeGreaterThanOrEqual(before + 60 * 60 * 1000);

    // an hour later
    await tdb
      .update(channelNotificationSettings)
      .set({ mutedUntil: Date.now() - 1000 })
      .where(eq(channelNotificationSettings.userId, 2));

    expect(await caller.notifications.getChannelSettings()).toEqual([]);
  });

  test('should refuse a length for anything but a mute', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.notifications.setChannelSetting({
        channelId: 1,
        level: 'all',
        muteForMinutes: 15
      })
    ).rejects.toThrow('Only a mute can last for a while.');
  });

  test('should silence a direct message while muted for a while, and push once it runs out', async () => {
    await registerDevices(3, 4);

    const { caller: sender } = await initTest(3);
    const { caller: muter } = await initTest(4);

    await muter.notifications.setChannelSetting({
      channelId: 3,
      level: 'none',
      muteForMinutes: 15
    });

    const spy = spyOnPushRelay();

    await sender.messages.send({ channelId: 3, content: 'quiet', files: [] });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([]);

    await tdb
      .update(channelNotificationSettings)
      .set({ mutedUntil: Date.now() - 1000 })
      .where(eq(channelNotificationSettings.userId, 4));

    await sender.messages.send({ channelId: 3, content: 'loud', files: [] });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([pushTicket(4)]);
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

    const spy = spyOnPushRelay();
    const { caller } = await initTest(1);

    await caller.messages.send({
      channelId: 1,
      content: '<p>nothing special</p>',
      files: []
    });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([pushTicket(2)]);
  });

  test('should push nothing from a muted channel, mentions included', async () => {
    await registerDevices(2);

    const { caller: member } = await initTest(2);

    await member.notifications.setChannelSetting({
      channelId: 1,
      level: 'none'
    });

    const spy = spyOnPushRelay();
    const { caller } = await initTest(1);

    await caller.messages.send({
      channelId: 1,
      content: MENTION_USER_2,
      files: []
    });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([]);
  });

  test('should push nothing from a muted direct message', async () => {
    await registerDevices(4);

    const { caller: userB } = await initTest(4);

    await userB.notifications.setChannelSetting({
      channelId: 3,
      level: 'none'
    });

    const spy = spyOnPushRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([]);
  });
});

describe('do not disturb', () => {
  test('should push nothing to someone set to do not disturb', async () => {
    await registerDevices(4);

    const { caller: userB } = await initTest(4);

    await userB.users.setPresence({ presence: 'dnd', customStatus: null });

    const spy = spyOnPushRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(pushedTickets(spy)).toEqual([]);
  });
});

describe('push through the relay', () => {
  test('should send the payload encrypted to the recipient only', async () => {
    await registerDevices(3, 4);

    const spy = spyOnPushRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(spy).toHaveBeenCalledTimes(1);

    const [notification] = spy.mock.calls[0]!;
    const { serverId } = await getSettings();

    expect(notification.ticket).toBe(pushTicket(4));
    expect(notification.encrypted).not.toContain('hey b');
    expect(await openPush(notification.encrypted)).toMatchObject({
      aps: { alert: { title: 'User A', body: 'hey b' } },
      serverId,
      channelId: 3
    });
  });

  test("should not open with another device's key", async () => {
    await registerDevices(4);

    const otherKey = await createPushKey();
    const spy = spyOnPushRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    const [notification] = spy.mock.calls[0]!;

    await expect(
      openPush(notification.encrypted, otherKey.privateKey)
    ).rejects.toThrow();
  });

  test.each(['BadTicket', 'ExpiredTicket', 'TicketNotForServer'])(
    'should forget a device the relay answers %s for',
    async (reason) => {
      await registerDevices(4);

      spyOnPushRelay(reason === 'TicketNotForServer' ? 403 : 410, reason);

      const { caller } = await initTest(3);

      await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
      await drainPushNotificationsQueue();

      expect(await tdb.select().from(pushDevices)).toHaveLength(0);
    }
  );

  test('should keep a device the relay is rate limiting', async () => {
    await registerDevices(4);

    spyOnPushRelay(429, 'TooManyRequests');

    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(await tdb.select().from(pushDevices)).toHaveLength(1);
  });
});

describe('the setting that turns push off', () => {
  test('should leave push on by default', async () => {
    const { pushRelayEnabled } = await getSettings();

    expect(pushRelayEnabled).toBe(true);
  });

  test('should store push as off', async () => {
    await turnPushOff();

    const { pushRelayEnabled } = await getSettings();

    expect(pushRelayEnabled).toBe(false);
  });

  test('should refuse to turn push off without permission to manage settings', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.others.updateSettings({ pushRelayEnabled: false })
    ).rejects.toThrow('Insufficient permissions');

    const { pushRelayEnabled } = await getSettings();

    expect(pushRelayEnabled).toBe(true);
  });
});
