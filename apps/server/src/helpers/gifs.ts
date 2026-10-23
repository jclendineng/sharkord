import { sha256, type TGifCategory, type TGifPage } from '@sharkord/shared';
import { getSettings } from '../db/queries/server';
import { invariant } from '../utils/invariant';
import { fetchKlipyGifs } from '../utils/klipy';

const PAGE_SIZE = 24;

// the searches the picker opens with, common reactions like discord's
const CATEGORY_TERMS = [
  'hello',
  'lol',
  'love',
  'thank you',
  'yes',
  'no',
  'wow',
  'sad',
  'happy',
  'dance',
  'party',
  'facepalm'
];

// the tiles change slowly and each is a request to klipy, so they are kept for a while
const CATEGORY_TTL_MS = 60 * 60 * 1000;

let cachedCategories:
  { at: number; key: string; categories: TGifCategory[] } | undefined;

const getKlipyKey = async () => {
  const { klipyApiKey, serverId } = await getSettings();

  invariant(klipyApiKey, {
    code: 'PRECONDITION_FAILED',
    message: "GIFs aren't set up on this server."
  });

  return { apiKey: klipyApiKey, serverId };
};

// stable per member and per server, so klipy can tell people apart without knowing who
const getCustomerId = async (serverId: string, userId: number) =>
  (await sha256(`${serverId}:${userId}`)).slice(0, 32);

const PROVIDER_ERROR = {
  code: 'BAD_GATEWAY',
  message: "Couldn't reach the GIF service, try again in a moment."
} as const;

const asProviderError = (): never => {
  invariant(false, PROVIDER_ERROR);
};

const getGifs = async (
  userId: number,
  options: { query?: string; page: number }
): Promise<TGifPage> => {
  const { apiKey, serverId } = await getKlipyKey();

  return fetchKlipyGifs({
    apiKey,
    customerId: await getCustomerId(serverId, userId),
    query: options.query,
    page: options.page,
    perPage: PAGE_SIZE
  }).catch(asProviderError);
};

const getGifCategories = async (userId: number): Promise<TGifCategory[]> => {
  const { apiKey, serverId } = await getKlipyKey();

  if (
    cachedCategories &&
    cachedCategories.key === apiKey &&
    Date.now() - cachedCategories.at < CATEGORY_TTL_MS
  ) {
    return cachedCategories.categories;
  }

  const customerId = await getCustomerId(serverId, userId);

  const pages = await Promise.all(
    CATEGORY_TERMS.map((term) =>
      fetchKlipyGifs({ apiKey, customerId, query: term, page: 1, perPage: 1 })
        .then((page) => ({ term, page }))
        .catch(() => undefined)
    )
  );

  const categories = pages.flatMap((result) => {
    const first = result?.page.gifs[0];

    return result && first
      ? [{ term: result.term, previewUrl: first.previewUrl }]
      : [];
  });

  invariant(categories.length > 0, PROVIDER_ERROR);

  cachedCategories = { at: Date.now(), key: apiKey, categories };

  return categories;
};

// tests start from a clean slate
const clearGifCategoryCache = () => {
  cachedCategories = undefined;
};

export { clearGifCategoryCache, getGifCategories, getGifs };
