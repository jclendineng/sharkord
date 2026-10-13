import { ServerEvents, type TTempFile } from '@sharkord/shared';
import { describe, expect, spyOn, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest, uploadFile } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { config } from '../../config';
import { messages, stickers } from '../../db/schema';
import { drainPushNotificationsQueue } from '../../queues/push-notifications';
import * as apns from '../../utils/apns';
import { pubsub } from '../../utils/pubsub';

const uploadSticker = async (
  token: string,
  name = 'wave.png',
  body: string | Uint8Array = 'sticker content'
) => {
  const file = new File([body], name, { type: 'image/png' });
  const response = await uploadFile(file, token);

  return (await response.json()) as TTempFile;
};

const addSticker = async (name = 'wave') => {
  const { caller, mockedToken } = await initTest(1);
  const upload = await uploadSticker(mockedToken);

  return caller.stickers.add({
    fileId: upload.id,
    name,
    description: 'says hi'
  });
};

describe('stickers.add', () => {
  test('should store the sticker with its file and tell everyone', async () => {
    const publish = spyOn(pubsub, 'publish');
    const stickerId = await addSticker();

    const sticker = await tdb
      .select()
      .from(stickers)
      .where(eq(stickers.id, stickerId))
      .get();

    expect(sticker).toMatchObject({
      name: 'wave',
      description: 'says hi',
      userId: 1
    });
    expect(sticker!.fileId).toBeNumber();

    await Bun.sleep(20);

    expect(
      publish.mock.calls.some(
        ([event]) => event === ServerEvents.STICKER_CREATE
      )
    ).toBe(true);
  });

  test('should refuse a file that is not an image a sticker can be', async () => {
    const { caller, mockedToken } = await initTest(1);
    const upload = await uploadSticker(mockedToken, 'notes.txt');

    await expect(
      caller.stickers.add({ fileId: upload.id, name: 'notes' })
    ).rejects.toThrow(
      'A sticker has to be a PNG, APNG, GIF or WebP image of 512 KB or less.'
    );
    expect(await tdb.select().from(stickers)).toHaveLength(0);
  });

  test('should refuse an image over 512 KB', async () => {
    const { caller, mockedToken } = await initTest(1);
    const upload = await uploadSticker(
      mockedToken,
      'big.png',
      new Uint8Array(600 * 1024)
    );

    await expect(
      caller.stickers.add({ fileId: upload.id, name: 'big' })
    ).rejects.toThrow(
      'A sticker has to be a PNG, APNG, GIF or WebP image of 512 KB or less.'
    );
  });

  test('should refuse an upload that is not there', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.stickers.add({ fileId: 'missing', name: 'gone' })
    ).rejects.toThrow(
      'That upload was not found, try adding the sticker again.'
    );
  });

  test('should refuse a name that is too short or too long', async () => {
    const { caller, mockedToken } = await initTest(1);
    const upload = await uploadSticker(mockedToken);

    await expect(
      caller.stickers.add({ fileId: upload.id, name: 'a' })
    ).rejects.toThrow();
    await expect(
      caller.stickers.add({ fileId: upload.id, name: 'a'.repeat(31) })
    ).rejects.toThrow();
  });

  test('should refuse someone without permission to manage emoji', async () => {
    const { caller, mockedToken } = await initTest(2);
    const upload = await uploadSticker(mockedToken);

    await expect(
      caller.stickers.add({ fileId: upload.id, name: 'wave' })
    ).rejects.toThrow('Insufficient permissions');
  });
});

describe('stickers.getAll', () => {
  test('should list the stickers for any member', async () => {
    await addSticker('wave');

    const { caller } = await initTest(2);
    const list = await caller.stickers.getAll();

    expect(list.map(({ name }) => name)).toEqual(['wave']);
    expect(list[0]!.file.name).toBeString();
  });

  test('should come with the server when joining', async () => {
    await addSticker('wave');

    const { caller } = await initTest(2);
    const { handshakeHash } = await caller.others.handshake();
    const joined = await caller.others.joinServer({ handshakeHash });

    expect(joined.stickers.map(({ name }) => name)).toEqual(['wave']);
  });
});

describe('stickers.update', () => {
  test('should rename the sticker', async () => {
    const stickerId = await addSticker();
    const { caller } = await initTest(1);

    await caller.stickers.update({ stickerId, name: 'hello', description: '' });

    const sticker = await tdb
      .select()
      .from(stickers)
      .where(eq(stickers.id, stickerId))
      .get();

    expect(sticker).toMatchObject({ name: 'hello', description: null });
    expect(sticker!.updatedAt).toBeNumber();
  });

  test('should refuse a sticker that does not exist', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.stickers.update({ stickerId: 999, name: 'hello' })
    ).rejects.toThrow('Sticker not found.');
  });

  test('should refuse someone without permission to manage emoji', async () => {
    const stickerId = await addSticker();
    const { caller } = await initTest(2);

    await expect(
      caller.stickers.update({ stickerId, name: 'hello' })
    ).rejects.toThrow('Insufficient permissions');
  });
});

describe('stickers.delete', () => {
  test('should remove the sticker and leave its messages showing it gone', async () => {
    const stickerId = await addSticker();
    const { caller } = await initTest(1);
    const messageId = await caller.messages.send({
      channelId: 1,
      content: '',
      stickerId
    });

    await caller.stickers.delete({ stickerId });

    expect(await tdb.select().from(stickers)).toHaveLength(0);

    const message = await tdb
      .select()
      .from(messages)
      .where(eq(messages.id, messageId))
      .get();

    expect(message?.stickerId).toBeNull();
  });

  test('should refuse a sticker that does not exist', async () => {
    const { caller } = await initTest(1);

    await expect(caller.stickers.delete({ stickerId: 999 })).rejects.toThrow(
      'Sticker not found.'
    );
  });

  test('should refuse someone without permission to manage emoji', async () => {
    const stickerId = await addSticker();
    const { caller } = await initTest(2);

    await expect(caller.stickers.delete({ stickerId })).rejects.toThrow(
      'Insufficient permissions'
    );
  });
});

describe('sending a sticker', () => {
  test('should send a message that is just the sticker', async () => {
    const stickerId = await addSticker();
    const { caller } = await initTest(2);

    const messageId = await caller.messages.send({
      channelId: 1,
      content: '',
      stickerId
    });

    const page = await caller.messages.get({
      channelId: 1,
      cursor: null,
      limit: 50
    });
    const message = page.messages.find(({ id }) => id === messageId);

    expect(message?.sticker).toMatchObject({ id: stickerId, name: 'wave' });

    const plain = page.messages.find(({ id }) => id !== messageId);

    expect(plain?.sticker).toBeNull();
  });

  test('should refuse a sticker that is not on the server', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.messages.send({ channelId: 1, content: '', stickerId: 999 })
    ).rejects.toThrow('That sticker is no longer on this server.');
  });

  test('should still refuse an empty message without a sticker', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.messages.send({ channelId: 1, content: '' })
    ).rejects.toThrow('Message cannot be empty.');
  });
});

describe('sticker push notifications', () => {
  test('should name the sticker in the push for a direct message', async () => {
    const stickerId = await addSticker('wave');
    const original = config.push.enabled;

    config.push.enabled = true;

    const { caller: userB } = await initTest(4);

    await userB.notifications.registerDevice({
      token: '4'.padStart(64, 'a'),
      sandbox: false
    });

    const spy = spyOn(apns, 'sendApnsNotification').mockResolvedValue({
      status: 200
    });

    try {
      const { caller: userA } = await initTest(3);

      await userA.messages.send({ channelId: 3, content: '', stickerId });
      await drainPushNotificationsQueue();
    } finally {
      config.push.enabled = original;
    }

    const [[notification]] = spy.mock.calls as unknown as [
      [apns.TApnsNotification]
    ];

    expect(notification.payload).toMatchObject({
      aps: { alert: { body: 'Sent a sticker: wave' } }
    });
  });
});
