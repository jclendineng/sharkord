import {
  ActivityLogType,
  ServerEvents,
  SOUND_MAX_VOLUME,
  SOUNDBOARD_LIBRARY,
  type TTempFile
} from '@sharkord/shared';
import { describe, expect, spyOn, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest, uploadFile } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { activityLog, files, soundboardSounds } from '../../db/schema';
import { pubsub } from '../../utils/pubsub';

const uploadSound = async (
  token: string,
  name = 'boop.mp3',
  body: string | Uint8Array = 'sound content'
) => {
  const file = new File([body], name, { type: 'audio/mpeg' });
  const response = await uploadFile(file, token);

  return (await response.json()) as TTempFile;
};

const addSound = async (name = 'boop') => {
  const { caller, mockedToken } = await initTest(1);
  const upload = await uploadSound(mockedToken);

  return caller.soundboard.add({
    fileId: upload.id,
    name,
    emoji: '🔔',
    volume: 80
  });
};

const getSound = (soundId: number) =>
  tdb
    .select()
    .from(soundboardSounds)
    .where(eq(soundboardSounds.id, soundId))
    .get();

describe('soundboard.add', () => {
  test('should store the sound with its file, tell everyone and log it', async () => {
    const publish = spyOn(pubsub, 'publish');
    const soundId = await addSound();

    expect(await getSound(soundId)).toMatchObject({
      name: 'boop',
      emoji: '🔔',
      volume: 80,
      libraryKey: null,
      userId: 1
    });

    await Bun.sleep(20);

    expect(
      publish.mock.calls.some(([event]) => event === ServerEvents.SOUND_CREATE)
    ).toBe(true);

    const entries = await tdb
      .select({ userId: activityLog.userId, details: activityLog.details })
      .from(activityLog)
      .where(eq(activityLog.type, ActivityLogType.CREATED_SOUND));

    expect(entries).toEqual([{ userId: 1, details: { name: 'boop' } }]);
  });

  test('should default to full volume and no emoji', async () => {
    const { caller, mockedToken } = await initTest(1);
    const upload = await uploadSound(mockedToken);
    const soundId = await caller.soundboard.add({
      fileId: upload.id,
      name: 'plain'
    });

    expect(await getSound(soundId)).toMatchObject({
      emoji: null,
      volume: 100
    });
  });

  test('should refuse a file that is not a sound', async () => {
    const { caller, mockedToken } = await initTest(1);
    const upload = await uploadSound(mockedToken, 'notes.txt');

    await expect(
      caller.soundboard.add({ fileId: upload.id, name: 'notes' })
    ).rejects.toThrow(
      'A sound has to be an MP3, WAV or M4A file of 512 KB or less.'
    );
    expect(await tdb.select().from(soundboardSounds)).toHaveLength(0);
  });

  test('should refuse a sound over 512 KB', async () => {
    const { caller, mockedToken } = await initTest(1);
    const upload = await uploadSound(
      mockedToken,
      'long.mp3',
      new Uint8Array(600 * 1024)
    );

    await expect(
      caller.soundboard.add({ fileId: upload.id, name: 'long' })
    ).rejects.toThrow(
      'A sound has to be an MP3, WAV or M4A file of 512 KB or less.'
    );
  });

  test('should refuse an upload that is not there', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.soundboard.add({ fileId: 'missing', name: 'gone' })
    ).rejects.toThrow('That upload was not found, try adding the sound again.');
  });

  test("should refuse someone else's upload", async () => {
    const { mockedToken } = await initTest(2);
    const upload = await uploadSound(mockedToken);
    const { caller } = await initTest(1);

    await expect(
      caller.soundboard.add({ fileId: upload.id, name: 'theirs' })
    ).rejects.toThrow('That upload was not found, try adding the sound again.');
  });

  test('should refuse a name that is too short or too long', async () => {
    const { caller, mockedToken } = await initTest(1);
    const upload = await uploadSound(mockedToken);

    await expect(
      caller.soundboard.add({ fileId: upload.id, name: 'a' })
    ).rejects.toThrow();
    await expect(
      caller.soundboard.add({ fileId: upload.id, name: 'a'.repeat(33) })
    ).rejects.toThrow();
  });

  test('should refuse a volume out of range', async () => {
    const { caller, mockedToken } = await initTest(1);
    const upload = await uploadSound(mockedToken);

    await expect(
      caller.soundboard.add({
        fileId: upload.id,
        name: 'loud',
        volume: SOUND_MAX_VOLUME + 1
      })
    ).rejects.toThrow();
    await expect(
      caller.soundboard.add({ fileId: upload.id, name: 'quiet', volume: -1 })
    ).rejects.toThrow();
  });

  test('should refuse someone without permission to manage the soundboard', async () => {
    const { caller, mockedToken } = await initTest(2);
    const upload = await uploadSound(mockedToken);

    await expect(
      caller.soundboard.add({ fileId: upload.id, name: 'boop' })
    ).rejects.toThrow('Insufficient permissions');
  });
});

describe('soundboard.addFromLibrary', () => {
  test('should copy the library sound into storage as a sound of its own', async () => {
    const publish = spyOn(pubsub, 'publish');
    const { caller } = await initTest(1);
    const soundId = await caller.soundboard.addFromLibrary({ key: 'you-win' });
    const sound = await getSound(soundId);

    expect(sound).toMatchObject({
      name: 'You Win',
      emoji: '🏆',
      volume: 100,
      libraryKey: 'you-win',
      userId: 1
    });

    const file = await tdb
      .select()
      .from(files)
      .where(eq(files.id, sound!.fileId))
      .get();

    expect(file?.size).toBeGreaterThan(0);

    await Bun.sleep(20);

    expect(
      publish.mock.calls.some(([event]) => event === ServerEvents.SOUND_CREATE)
    ).toBe(true);
  });

  test('should refuse a library sound the server already has', async () => {
    const { caller } = await initTest(1);

    await caller.soundboard.addFromLibrary({ key: 'ding' });

    await expect(
      caller.soundboard.addFromLibrary({ key: 'ding' })
    ).rejects.toThrow('This server already has that sound.');
  });

  test('should allow it again once deleted', async () => {
    const { caller } = await initTest(1);
    const soundId = await caller.soundboard.addFromLibrary({ key: 'ding' });

    await caller.soundboard.delete({ soundId });

    await expect(
      caller.soundboard.addFromLibrary({ key: 'ding' })
    ).resolves.toBeNumber();
  });

  test('should refuse a key that is not in the library', async () => {
    const { caller } = await initTest(1);

    await expect(
      // @ts-expect-error a key the library does not have
      caller.soundboard.addFromLibrary({ key: 'airhorn' })
    ).rejects.toThrow();
  });

  test('should refuse someone without permission to manage the soundboard', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.soundboard.addFromLibrary({ key: 'ding' })
    ).rejects.toThrow('Insufficient permissions');
  });
});

describe('soundboard.getAll', () => {
  test('should list the sounds for any member', async () => {
    await addSound('boop');

    const { caller } = await initTest(2);
    const list = await caller.soundboard.getAll();

    expect(list.map(({ name }) => name)).toEqual(['boop']);
    expect(list[0]!.file.name).toBeString();
  });

  test('should come with the server when joining', async () => {
    await addSound('boop');

    const { caller } = await initTest(2);
    const { handshakeHash } = await caller.others.handshake();
    const joined = await caller.others.joinServer({ handshakeHash });

    expect(joined.sounds.map(({ name }) => name)).toEqual(['boop']);
  });
});

describe('soundboard.getLibrary', () => {
  test('should list the library for any member', async () => {
    const { caller } = await initTest(2);
    const library = await caller.soundboard.getLibrary();

    expect(library.map(({ key }) => key)).toEqual(
      SOUNDBOARD_LIBRARY.map(({ key }) => key)
    );
  });
});

describe('soundboard.update', () => {
  test('should change the name, emoji and volume and tell everyone', async () => {
    const soundId = await addSound();
    const publish = spyOn(pubsub, 'publish');
    const { caller } = await initTest(1);

    await caller.soundboard.update({
      soundId,
      name: 'beep',
      emoji: '',
      volume: 40
    });

    const sound = await getSound(soundId);

    expect(sound).toMatchObject({ name: 'beep', emoji: null, volume: 40 });
    expect(sound!.updatedAt).toBeNumber();

    await Bun.sleep(20);

    expect(
      publish.mock.calls.some(([event]) => event === ServerEvents.SOUND_UPDATE)
    ).toBe(true);
  });

  test('should refuse a sound that does not exist', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.soundboard.update({ soundId: 999, name: 'beep', volume: 50 })
    ).rejects.toThrow('Sound not found.');
  });

  test('should refuse someone without permission to manage the soundboard', async () => {
    const soundId = await addSound();
    const { caller } = await initTest(2);

    await expect(
      caller.soundboard.update({ soundId, name: 'beep', volume: 50 })
    ).rejects.toThrow('Insufficient permissions');
  });
});

describe('soundboard.delete', () => {
  test('should remove the sound and its file and tell everyone', async () => {
    const soundId = await addSound();
    const { fileId } = (await getSound(soundId))!;
    const publish = spyOn(pubsub, 'publish');
    const { caller } = await initTest(1);

    await caller.soundboard.delete({ soundId });

    expect(await tdb.select().from(soundboardSounds)).toHaveLength(0);
    expect(
      await tdb.select().from(files).where(eq(files.id, fileId)).get()
    ).toBeUndefined();
    expect(publish).toHaveBeenCalledWith(ServerEvents.SOUND_DELETE, soundId);
  });

  test('should refuse a sound that does not exist', async () => {
    const { caller } = await initTest(1);

    await expect(caller.soundboard.delete({ soundId: 999 })).rejects.toThrow(
      'Sound not found.'
    );
  });

  test('should refuse someone without permission to manage the soundboard', async () => {
    const soundId = await addSound();
    const { caller } = await initTest(2);

    await expect(caller.soundboard.delete({ soundId })).rejects.toThrow(
      'Insufficient permissions'
    );
  });
});
