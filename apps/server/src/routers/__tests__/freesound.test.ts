import { describe, expect, spyOn, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { activityLog, settings, soundboardSounds } from '../../db/schema';
import { drainActivityLogQueue } from '../../queues/activity-log';

/**
 * Freesound itself is not reached: the harness has no network, so fetch is spied for
 * freesound's addresses and everything else passes through to the real one.
 */

const CC0 = 'http://creativecommons.org/publicdomain/zero/1.0/';
const CC_BY = 'https://creativecommons.org/licenses/by/4.0/';
const CC_BY_NC = 'https://creativecommons.org/licenses/by-nc/4.0/';

type TItem = {
  id: number;
  name: string;
  username: string;
  license: string;
  duration: number;
  previews: Record<string, string>;
};

const freesoundItem = (id: number, overrides: Partial<TItem> = {}): TItem => ({
  id,
  name: `horn ${id}.wav`,
  username: 'maker',
  license: CC0,
  duration: 2,
  previews: {
    'preview-hq-mp3': `https://cdn.freesound.org/previews/${id}-hq.mp3`
  },
  ...overrides
});

const spyOnFreesound = (
  items: TItem[] = [freesoundItem(1), freesoundItem(2)],
  options: { next?: string | null; previewBytes?: number } = {}
) => {
  const realFetch = globalThis.fetch;
  const requests: { url: URL; init?: RequestInit }[] = [];

  const spy = spyOn(globalThis, 'fetch').mockImplementation((async (
    input: string | URL | Request,
    init?: RequestInit
  ) => {
    const url = new URL(String(input));

    if (url.hostname === 'cdn.freesound.org') {
      return new Response(new Uint8Array(options.previewBytes ?? 1024), {
        headers: { 'Content-Type': 'audio/mpeg' }
      });
    }

    if (url.hostname !== 'freesound.org') {
      return realFetch(input, init);
    }

    requests.push({ url, init });

    const soundMatch = url.pathname.match(/\/sounds\/(\d+)\//);

    if (soundMatch) {
      const item = items.find(({ id }) => id === Number(soundMatch[1]));

      return item
        ? new Response(JSON.stringify(item))
        : new Response('{}', { status: 404 });
    }

    return new Response(
      JSON.stringify({ results: items, next: options.next ?? null })
    );
  }) as typeof fetch);

  return { spy, requests };
};

const setKey = async () => {
  const { caller } = await initTest(1);

  await caller.others.updateSettings({ freesoundApiKey: 'sound-key' });
};

describe('soundboard.searchFreesound', () => {
  test('should search freesound with the key and only free to reuse licenses', async () => {
    await setKey();

    const { requests } = spyOnFreesound(
      [
        freesoundItem(1),
        freesoundItem(2, { license: CC_BY }),
        freesoundItem(3, { license: CC_BY_NC })
      ],
      { next: 'https://freesound.org/apiv2/search/text/?page=2' }
    );
    const { caller } = await initTest(1);
    const page = await caller.soundboard.searchFreesound({ query: 'horn' });

    expect(page.sounds.map(({ id, license }) => ({ id, license }))).toEqual([
      { id: 1, license: 'CC0' },
      { id: 2, license: 'CC BY' }
    ]);
    expect(page.sounds[0]).toMatchObject({
      name: 'horn 1',
      username: 'maker',
      previewUrl: 'https://cdn.freesound.org/previews/1-hq.mp3'
    });
    expect(page.hasMore).toBe(true);

    const [request] = requests;

    expect(request!.url.searchParams.get('query')).toBe('horn');
    expect(request!.url.searchParams.get('filter')).toContain(
      'Creative Commons 0'
    );
    expect(new Headers(request!.init?.headers).get('Authorization')).toBe(
      'Token sound-key'
    );
  });

  test('should refuse when no key is set', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.soundboard.searchFreesound({ query: 'horn' })
    ).rejects.toThrow("Sound search isn't set up on this server.");
  });

  test('should say so when freesound does not answer', async () => {
    await setKey();

    const realFetch = globalThis.fetch;

    spyOn(globalThis, 'fetch').mockImplementation((async (
      input: string | URL | Request,
      init?: RequestInit
    ) => {
      if (new URL(String(input)).hostname === 'freesound.org') {
        return new Response('down', { status: 503 });
      }

      return realFetch(input, init);
    }) as typeof fetch);

    const { caller } = await initTest(1);

    await expect(
      caller.soundboard.searchFreesound({ query: 'horn' })
    ).rejects.toThrow("Couldn't reach Freesound, try again in a moment.");
  });

  test('should refuse an empty search', async () => {
    await setKey();

    const { caller } = await initTest(1);

    await expect(
      caller.soundboard.searchFreesound({ query: '  ' })
    ).rejects.toThrow();
  });

  test('should refuse someone without permission to manage the soundboard', async () => {
    await setKey();

    const { caller } = await initTest(2);

    await expect(
      caller.soundboard.searchFreesound({ query: 'horn' })
    ).rejects.toThrow('Insufficient permissions');
  });
});

describe('soundboard.addFromFreesound', () => {
  test('should download the preview into storage with its credit', async () => {
    await setKey();
    spyOnFreesound([freesoundItem(7, { license: CC_BY })]);

    const { caller } = await initTest(1);
    const soundId = await caller.soundboard.addFromFreesound({
      freesoundId: 7
    });
    const sound = await tdb
      .select()
      .from(soundboardSounds)
      .where(eq(soundboardSounds.id, soundId))
      .get();

    expect(sound).toMatchObject({
      name: 'horn 7',
      libraryKey: 'freesound:7',
      attribution: '"horn 7" by maker on Freesound, CC BY',
      volume: 100,
      userId: 1
    });
  });

  test('should refuse a sound the server already has', async () => {
    await setKey();
    spyOnFreesound([freesoundItem(7)]);

    const { caller } = await initTest(1);

    await caller.soundboard.addFromFreesound({ freesoundId: 7 });

    await expect(
      caller.soundboard.addFromFreesound({ freesoundId: 7 })
    ).rejects.toThrow('This server already has that sound.');
  });

  test('should refuse a sound under a license that does not allow reuse', async () => {
    await setKey();
    spyOnFreesound([freesoundItem(8, { license: CC_BY_NC })]);

    const { caller } = await initTest(1);

    await expect(
      caller.soundboard.addFromFreesound({ freesoundId: 8 })
    ).rejects.toThrow("That sound isn't available to add.");
  });

  test('should refuse a preview that is not on freesound', async () => {
    await setKey();
    spyOnFreesound([
      freesoundItem(9, {
        previews: { 'preview-hq-mp3': 'https://example.com/9.mp3' }
      })
    ]);

    const { caller } = await initTest(1);

    await expect(
      caller.soundboard.addFromFreesound({ freesoundId: 9 })
    ).rejects.toThrow("That sound isn't available to add.");
  });

  test('should refuse a sound longer than ten seconds', async () => {
    await setKey();
    spyOnFreesound([freesoundItem(10, { duration: 30 })]);

    const { caller } = await initTest(1);

    await expect(
      caller.soundboard.addFromFreesound({ freesoundId: 10 })
    ).rejects.toThrow('A sound can be 10 seconds at most.');
  });

  test('should refuse a preview over 512 KB', async () => {
    await setKey();
    spyOnFreesound([freesoundItem(11)], { previewBytes: 600 * 1024 });

    const { caller } = await initTest(1);

    await expect(
      caller.soundboard.addFromFreesound({ freesoundId: 11 })
    ).rejects.toThrow('That sound is over 512 KB, the most a sound can be.');
    expect(await tdb.select().from(soundboardSounds)).toHaveLength(0);
  });

  test('should refuse when no key is set', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.soundboard.addFromFreesound({ freesoundId: 7 })
    ).rejects.toThrow("Sound search isn't set up on this server.");
  });

  test('should refuse someone without permission to manage the soundboard', async () => {
    await setKey();

    const { caller } = await initTest(2);

    await expect(
      caller.soundboard.addFromFreesound({ freesoundId: 7 })
    ).rejects.toThrow('Insufficient permissions');
  });
});

describe('freesound in server settings', () => {
  test('should tell members sound search is on without showing them the key', async () => {
    await setKey();

    const row = await tdb
      .select({ key: settings.freesoundApiKey })
      .from(settings)
      .get();

    expect(row?.key).toBe('sound-key');

    const { caller } = await initTest(2);
    const { handshakeHash } = await caller.others.handshake();
    const joined = await caller.others.joinServer({ handshakeHash });

    expect(joined.publicSettings.soundSearchEnabled).toBe(true);
    expect(JSON.stringify(joined)).not.toContain('sound-key');
  });

  test('should keep the key out of the activity log', async () => {
    await setKey();

    await drainActivityLogQueue();

    const logs = await tdb.select().from(activityLog);

    expect(logs.length).toBeGreaterThan(0);
    expect(JSON.stringify(logs)).not.toContain('sound-key');
  });
});
