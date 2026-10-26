import { afterAll, beforeEach, describe, expect, spyOn, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { config } from '../../config';
import { getSettings } from '../../db/queries/server';
import {
  channelNotificationSettings,
  pushDevices,
  users
} from '../../db/schema';
import { drainPushNotificationsQueue } from '../../queues/push-notifications';
import * as apns from '../../utils/apns';
import * as pushRelay from '../../utils/push-relay';

/**
 * APNs itself is not reached: the harness has no network to apple and no key to sign with,
 * so sendApnsNotification is spied and everything that decides who it is called for is
 * covered here instead. the push relay is spied the same way, its signed request is covered
 * in utils/__tests__/push-relay.test.ts and the relay itself in apps/push-relay.
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

describe('message previews in push', () => {
  test('should show the content by default', async () => {
    const { pushShowMessageContent } = await getSettings();

    expect(pushShowMessageContent).toBe(true);
  });

  test('should leave out the content of a direct message when previews are off', async () => {
    await registerDevices(4);

    const { caller: owner } = await initTest(1);

    await owner.others.updateSettings({ pushShowMessageContent: false });

    const spy = spyOnApns();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    const [[notification]] = spy.mock.calls as unknown as [
      [apns.TApnsNotification]
    ];

    expect(notification.payload).toMatchObject({
      aps: { alert: { title: 'User A', body: 'Sent you a direct message' } },
      channelId: 3
    });
    expect(JSON.stringify(notification.payload)).not.toContain('hey b');
  });

  test('should leave out the content and the channel of a mention when previews are off', async () => {
    await registerDevices(2);

    const { caller } = await initTest(1);

    await caller.others.updateSettings({ pushShowMessageContent: false });

    const spy = spyOnApns();

    await caller.messages.send({
      channelId: 1,
      content:
        '<p><span data-type="mention" data-user-id="2" class="mention">@Test User</span> secret plans</p>',
      files: []
    });
    await drainPushNotificationsQueue();

    const [[notification]] = spy.mock.calls as unknown as [
      [apns.TApnsNotification]
    ];

    expect(notification.payload).toMatchObject({
      aps: { alert: { title: 'Test Owner', body: 'Sent a message' } }
    });
    expect(JSON.stringify(notification.payload)).not.toContain('secret plans');
    expect(JSON.stringify(notification.payload)).not.toContain('General');
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

    const spy = spyOnApns();

    await sender.messages.send({ channelId: 3, content: 'quiet', files: [] });
    await drainPushNotificationsQueue();

    expect(notifiedTokens(spy)).toEqual([]);

    await tdb
      .update(channelNotificationSettings)
      .set({ mutedUntil: Date.now() - 1000 })
      .where(eq(channelNotificationSettings.userId, 4));

    await sender.messages.send({ channelId: 3, content: 'loud', files: [] });
    await drainPushNotificationsQueue();

    expect(notifiedTokens(spy)).toEqual([deviceToken(4)]);
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

describe('do not disturb', () => {
  test('should push nothing to someone set to do not disturb', async () => {
    await registerDevices(4);

    const { caller: userB } = await initTest(4);

    await userB.users.setPresence({ presence: 'dnd', customStatus: null });

    const spy = spyOnApns();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(notifiedTokens(spy)).toEqual([]);
  });
});

describe('push through the relay', () => {
  const RELAY_URL = 'https://relay.test';

  type TDeviceKey = { privateKey: CryptoKey; encryptionKey: string };

  // what the app does: a p-256 key pair per server, the public half sent as x963 base64url
  const createDeviceKey = async (): Promise<TDeviceKey> => {
    const pair = (await crypto.subtle.generateKey(
      { name: 'ECDH', namedCurve: 'P-256' },
      true,
      ['deriveBits']
    )) as CryptoKeyPair;
    const raw = await crypto.subtle.exportKey('raw', pair.publicKey);

    return {
      privateKey: pair.privateKey,
      encryptionKey: Buffer.from(raw).toString('base64url')
    };
  };

  // the app's side of utils/push-encryption, so a test proves the payload opens
  const decrypt = async (privateKey: CryptoKey, encrypted: string) => {
    const bytes = Buffer.from(encrypted, 'base64url');
    const ephemeralPublicKey = bytes.subarray(0, 65);
    const ephemeral = await crypto.subtle.importKey(
      'raw',
      ephemeralPublicKey,
      { name: 'ECDH', namedCurve: 'P-256' },
      false,
      []
    );
    const sharedSecret = await crypto.subtle.deriveBits(
      { name: 'ECDH', public: ephemeral },
      privateKey,
      256
    );
    const hkdfKey = await crypto.subtle.importKey(
      'raw',
      sharedSecret,
      'HKDF',
      false,
      ['deriveKey']
    );
    const aesKey = await crypto.subtle.deriveKey(
      {
        name: 'HKDF',
        hash: 'SHA-256',
        salt: ephemeralPublicKey,
        info: new TextEncoder().encode('sharkord push v1')
      },
      hkdfKey,
      { name: 'AES-GCM', length: 256 },
      false,
      ['decrypt']
    );
    const opened = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: bytes.subarray(65, 77) },
      aesKey,
      bytes.subarray(77)
    );

    return JSON.parse(new TextDecoder().decode(opened));
  };

  const relayId = (userId: number) => `${userId}`.padStart(64, 'c');
  const relayTicket = (userId: number) => `ticket-for-${userId}`;

  const registerRelayDevice = async (userId: number) => {
    const key = await createDeviceKey();
    const { caller } = await initTest(userId);

    await caller.notifications.registerDevice({
      token: relayId(userId),
      relayTicket: relayTicket(userId),
      encryptionKey: key.encryptionKey
    });

    return key;
  };

  const spyOnRelay = (status = 200, reason?: string) =>
    spyOn(pushRelay, 'sendRelayNotification').mockResolvedValue({
      status,
      reason
    });

  beforeEach(() => {
    config.push.enabled = false;
    config.push.relayUrl = RELAY_URL;
  });

  test('should store the ticket and key without a server apns key', async () => {
    const key = await registerRelayDevice(2);

    const device = await tdb
      .select()
      .from(pushDevices)
      .where(eq(pushDevices.token, relayId(2)))
      .get();

    expect(device?.userId).toBe(2);
    expect(device?.relayTicket).toBe(relayTicket(2));
    expect(device?.encryptionKey).toBe(key.encryptionKey);
    expect(device?.sandbox).toBe(false);
  });

  test('should replace the ticket when the app refreshes it', async () => {
    const key = await createDeviceKey();
    const { caller } = await initTest(2);

    await caller.notifications.registerDevice({
      token: relayId(2),
      relayTicket: 'first',
      encryptionKey: key.encryptionKey
    });
    await caller.notifications.registerDevice({
      token: relayId(2),
      relayTicket: 'second',
      encryptionKey: key.encryptionKey
    });

    const devices = await tdb.select().from(pushDevices);

    expect(devices).toHaveLength(1);
    expect(devices[0]!.relayTicket).toBe('second');
  });

  test('should refuse a relay device when the server has no relay', async () => {
    config.push.relayUrl = '';
    config.push.enabled = true;

    const key = await createDeviceKey();
    const { caller } = await initTest(2);

    await expect(
      caller.notifications.registerDevice({
        token: relayId(2),
        relayTicket: relayTicket(2),
        encryptionKey: key.encryptionKey
      })
    ).rejects.toThrow('Push notifications are not enabled on this server.');
  });

  test('should refuse a direct token when the server only has the relay', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.notifications.registerDevice({
        token: deviceToken(2),
        sandbox: false
      })
    ).rejects.toThrow('Push notifications are not enabled on this server.');
  });

  test('should refuse an encryption key that is not a p-256 point', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.notifications.registerDevice({
        token: relayId(2),
        relayTicket: relayTicket(2),
        encryptionKey: 'A'.repeat(87)
      })
    ).rejects.toThrow('This device sent an encryption key that is not valid.');

    expect(await tdb.select().from(pushDevices)).toHaveLength(0);
  });

  test('should refuse a ticket with characters a ticket never has', async () => {
    const key = await createDeviceKey();
    const { caller } = await initTest(2);

    await expect(
      caller.notifications.registerDevice({
        token: relayId(2),
        relayTicket: 'not a ticket!',
        encryptionKey: key.encryptionKey
      })
    ).rejects.toThrow();

    expect(await tdb.select().from(pushDevices)).toHaveLength(0);
  });

  test('should send the payload encrypted to the recipient only', async () => {
    const [, recipientKey] = await Promise.all([
      registerRelayDevice(3),
      registerRelayDevice(4)
    ]);
    const spy = spyOnRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(spy).toHaveBeenCalledTimes(1);

    const [notification] = spy.mock.calls[0]!;
    const { serverId } = await getSettings();

    expect(notification.ticket).toBe(relayTicket(4));
    expect(notification.encrypted).not.toContain('hey b');
    expect(
      await decrypt(recipientKey.privateKey, notification.encrypted)
    ).toMatchObject({
      aps: { alert: { title: 'User A', body: 'hey b' } },
      serverId,
      channelId: 3
    });
  });

  test("should not open with another device's key", async () => {
    await registerRelayDevice(4);

    const otherKey = await createDeviceKey();
    const spy = spyOnRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    const [notification] = spy.mock.calls[0]!;

    await expect(
      decrypt(otherKey.privateKey, notification.encrypted)
    ).rejects.toThrow();
  });

  test('should skip a direct device while the server has no apns key', async () => {
    await tdb.insert(pushDevices).values({
      userId: 4,
      token: deviceToken(4),
      tokenVersion: 0,
      sandbox: false,
      createdAt: Date.now()
    });

    const apnsSpy = spyOnApns();
    const relaySpy = spyOnRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(apnsSpy).not.toHaveBeenCalled();
    expect(relaySpy).not.toHaveBeenCalled();
    expect(await tdb.select().from(pushDevices)).toHaveLength(1);
  });

  test('should skip a relay device once the relay is turned off', async () => {
    await registerRelayDevice(4);

    config.push.relayUrl = '';
    config.push.enabled = true;

    const apnsSpy = spyOnApns();
    const relaySpy = spyOnRelay();
    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(apnsSpy).not.toHaveBeenCalled();
    expect(relaySpy).not.toHaveBeenCalled();
  });

  test.each(['BadTicket', 'ExpiredTicket', 'TicketNotForServer'])(
    'should forget a device the relay answers %s for',
    async (reason) => {
      await registerRelayDevice(4);

      spyOnRelay(reason === 'TicketNotForServer' ? 403 : 410, reason);

      const { caller } = await initTest(3);

      await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
      await drainPushNotificationsQueue();

      expect(await tdb.select().from(pushDevices)).toHaveLength(0);
    }
  );

  test('should keep a device the relay is rate limiting', async () => {
    await registerRelayDevice(4);

    spyOnRelay(429, 'TooManyRequests');

    const { caller } = await initTest(3);

    await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
    await drainPushNotificationsQueue();

    expect(await tdb.select().from(pushDevices)).toHaveLength(1);
  });

  describe('the setting that turns the relay off', () => {
    test('should leave the relay on by default', async () => {
      const { pushRelayEnabled } = await getSettings();

      expect(pushRelayEnabled).toBe(true);
    });

    test('should store the relay as off', async () => {
      const { caller } = await initTest(1);

      await caller.others.updateSettings({ pushRelayEnabled: false });

      const { pushRelayEnabled } = await getSettings();

      expect(pushRelayEnabled).toBe(false);
    });

    test('should refuse to turn the relay off without permission to manage settings', async () => {
      const { caller } = await initTest(2);

      await expect(
        caller.others.updateSettings({ pushRelayEnabled: false })
      ).rejects.toThrow('Insufficient permissions');

      const { pushRelayEnabled } = await getSettings();

      expect(pushRelayEnabled).toBe(true);
    });

    test('should refuse a relay device while the relay is turned off', async () => {
      const { caller: owner } = await initTest(1);

      await owner.others.updateSettings({ pushRelayEnabled: false });

      const key = await createDeviceKey();
      const { caller } = await initTest(2);

      await expect(
        caller.notifications.registerDevice({
          token: relayId(2),
          relayTicket: relayTicket(2),
          encryptionKey: key.encryptionKey
        })
      ).rejects.toThrow('Push notifications are not enabled on this server.');

      expect(await tdb.select().from(pushDevices)).toHaveLength(0);
    });

    test('should still take a direct token while the relay is turned off', async () => {
      config.push.enabled = true;

      const { caller: owner } = await initTest(1);

      await owner.others.updateSettings({ pushRelayEnabled: false });
      await registerDevices(2);

      expect(await tdb.select().from(pushDevices)).toHaveLength(1);
    });

    test('should send nothing to the relay while it is turned off', async () => {
      await registerRelayDevice(4);

      const { caller: owner } = await initTest(1);

      await owner.others.updateSettings({ pushRelayEnabled: false });

      const relaySpy = spyOnRelay();
      const { caller } = await initTest(3);

      await caller.messages.send({ channelId: 3, content: 'hey b', files: [] });
      await drainPushNotificationsQueue();

      expect(relaySpy).not.toHaveBeenCalled();
      expect(await tdb.select().from(pushDevices)).toHaveLength(1);
    });
  });
});
