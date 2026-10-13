import { Permission } from '@sharkord/shared';
import { afterEach, beforeEach, describe, expect, spyOn, test } from 'bun:test';
import { and, eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { config } from '../../config';
import { activityLog, rolePermissions, settings } from '../../db/schema';
import { clearGifCategoryCache } from '../../helpers/gifs';
import { drainActivityLogQueue } from '../../queues/activity-log';

/**
 * Klipy itself is not reached: the harness has no network, so fetch is spied for klipy's
 * address and everything else passes through to the real one.
 */

const klipyGif = (id: number, title = `gif ${id}`) => ({
  id,
  title,
  file: {
    sm: {
      gif: {
        url: `https://static.klipy.com/${id}/sm.gif`,
        width: 100,
        height: 80
      }
    },
    md: {
      gif: {
        url: `https://static.klipy.com/${id}/md.gif`,
        width: 300,
        height: 240
      }
    }
  }
});

const spyOnKlipy = (items = [klipyGif(1), klipyGif(2)], totalPages = 3) => {
  const realFetch = globalThis.fetch;
  const requests: URL[] = [];

  const spy = spyOn(globalThis, 'fetch').mockImplementation((async (
    input: string | URL | Request,
    init?: RequestInit
  ) => {
    const url = new URL(String(input));

    if (url.hostname !== 'api.klipy.com') {
      return realFetch(input, init);
    }

    requests.push(url);

    return new Response(
      JSON.stringify({
        data: {
          data: items,
          pagination: {
            page: Number(url.searchParams.get('page')),
            total_pages: totalPages
          }
        }
      })
    );
  }) as typeof fetch);

  return { spy, requests };
};

const setKey = async () => {
  const { caller } = await initTest(1);

  await caller.others.updateSettings({ klipyApiKey: 'test-key' });
};

beforeEach(() => {
  clearGifCategoryCache();
});

afterEach(() => {
  config.gifs.klipyApiKey = '';
});

describe('gifs.trending', () => {
  test('should return trending gifs from klipy', async () => {
    await setKey();

    const { requests } = spyOnKlipy();
    const { caller } = await initTest(2);
    const page = await caller.gifs.trending({ page: 1 });

    expect(page).toEqual({
      gifs: [
        {
          id: '1',
          title: 'gif 1',
          url: 'https://static.klipy.com/1/md.gif',
          previewUrl: 'https://static.klipy.com/1/sm.gif',
          width: 300,
          height: 240
        },
        {
          id: '2',
          title: 'gif 2',
          url: 'https://static.klipy.com/2/md.gif',
          previewUrl: 'https://static.klipy.com/2/sm.gif',
          width: 300,
          height: 240
        }
      ],
      hasMore: true
    });

    expect(requests[0]!.pathname).toBe('/api/v1/test-key/gifs/trending');
  });

  test('should tag each member with an id that does not name them', async () => {
    await setKey();

    const { requests } = spyOnKlipy();
    const { caller: first } = await initTest(2);
    const { caller: second } = await initTest(3);

    await first.gifs.trending({ page: 1 });
    await second.gifs.trending({ page: 1 });

    const [a, b] = requests.map((url) => url.searchParams.get('customer_id'));

    expect(a).toHaveLength(32);
    expect(a).not.toBe(b);
    expect(a).not.toBe('2');
  });

  test('should refuse when no key is set', async () => {
    const { caller } = await initTest(2);

    await expect(caller.gifs.trending({ page: 1 })).rejects.toThrow(
      "GIFs aren't set up on this server."
    );
  });

  test('should say so when klipy does not answer', async () => {
    await setKey();

    const realFetch = globalThis.fetch;

    spyOn(globalThis, 'fetch').mockImplementation((async (
      input: string | URL | Request,
      init?: RequestInit
    ) =>
      new URL(String(input)).hostname === 'api.klipy.com'
        ? new Response('nope', { status: 500 })
        : realFetch(input, init)) as typeof fetch);

    const { caller } = await initTest(2);

    await expect(caller.gifs.trending({ page: 1 })).rejects.toThrow(
      "Couldn't reach the GIF service, try again in a moment."
    );
  });

  test('should refuse someone without permission to send messages', async () => {
    await setKey();

    await tdb
      .delete(rolePermissions)
      .where(
        and(
          eq(rolePermissions.roleId, 2),
          eq(rolePermissions.permission, Permission.SEND_MESSAGES)
        )
      );

    const { caller } = await initTest(2);

    await expect(caller.gifs.trending({ page: 1 })).rejects.toThrow(
      'Insufficient permissions'
    );
  });
});

describe('gifs.search', () => {
  test('should search klipy and say when the last page is reached', async () => {
    await setKey();

    const { requests } = spyOnKlipy([klipyGif(5, 'cat')], 2);
    const { caller } = await initTest(2);
    const page = await caller.gifs.search({ query: 'cat', page: 2 });

    expect(page.gifs.map(({ title }) => title)).toEqual(['cat']);
    expect(page.hasMore).toBe(false);
    expect(requests[0]!.pathname).toBe('/api/v1/test-key/gifs/search');
    expect(requests[0]!.searchParams.get('q')).toBe('cat');
  });

  test('should refuse an empty search', async () => {
    await setKey();

    const { caller } = await initTest(2);

    await expect(
      caller.gifs.search({ query: '  ', page: 1 })
    ).rejects.toThrow();
  });
});

describe('gifs.categories', () => {
  test('should give each tile a gif to show behind it, and keep them for a while', async () => {
    await setKey();

    const { requests } = spyOnKlipy([klipyGif(9)]);
    const { caller } = await initTest(2);
    const categories = await caller.gifs.categories();

    expect(categories[0]).toEqual({
      term: 'hello',
      previewUrl: 'https://static.klipy.com/9/sm.gif'
    });

    const firstRound = requests.length;

    await caller.gifs.categories();

    expect(requests.length).toBe(firstRound);
  });
});

describe('gifs in server settings', () => {
  test('should tell members gifs are on without showing them the key', async () => {
    await setKey();

    const row = await tdb
      .select({ key: settings.klipyApiKey })
      .from(settings)
      .get();

    expect(row?.key).toBe('test-key');

    const { caller } = await initTest(2);
    const { handshakeHash } = await caller.others.handshake();
    const joined = await caller.others.joinServer({ handshakeHash });

    expect(joined.publicSettings.gifsEnabled).toBe(true);
    expect(JSON.stringify(joined)).not.toContain('test-key');
  });

  test('should keep the key out of the activity log', async () => {
    await setKey();

    await drainActivityLogQueue();

    const logs = await tdb.select().from(activityLog);

    expect(logs.length).toBeGreaterThan(0);
    expect(JSON.stringify(logs)).not.toContain('test-key');
  });
});

describe('gifs from config.ini', () => {
  test('should use the key from config.ini when none is saved', async () => {
    config.gifs.klipyApiKey = 'ini-key';

    const { requests } = spyOnKlipy();
    const { caller } = await initTest(2);

    await caller.gifs.trending({ page: 1 });

    expect(requests[0]!.pathname).toBe('/api/v1/ini-key/gifs/trending');

    const { handshakeHash } = await caller.others.handshake();
    const joined = await caller.others.joinServer({ handshakeHash });

    expect(joined.publicSettings.gifsEnabled).toBe(true);
    expect(JSON.stringify(joined)).not.toContain('ini-key');
  });

  test('should prefer the key saved in settings', async () => {
    config.gifs.klipyApiKey = 'ini-key';

    await setKey();

    const { requests } = spyOnKlipy();
    const { caller } = await initTest(2);

    await caller.gifs.trending({ page: 1 });

    expect(requests[0]!.pathname).toBe('/api/v1/test-key/gifs/trending');
  });
});
