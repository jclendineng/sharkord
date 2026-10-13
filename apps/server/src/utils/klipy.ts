import type { TGif, TGifPage } from '@sharkord/shared';
import { config } from '../config';

// klipy, the gif provider discord uses. the key stays on the server, members' searches reach
// klipy from here, each tagged with an id that tells members apart without naming them
const KLIPY_BASE_URL = 'https://api.klipy.com/api/v1';

// the key from the settings screen, or from config.ini when none is saved there
const resolveKlipyApiKey = (settingsKey: string | null): string | null =>
  settingsKey || config.gifs.klipyApiKey || null;

type TKlipyRendition = {
  url?: string;
  width?: number;
  height?: number;
};

type TKlipyItem = {
  id: number | string;
  title?: string;
  file?: {
    sm?: { gif?: TKlipyRendition };
    md?: { gif?: TKlipyRendition };
    hd?: { gif?: TKlipyRendition };
  };
};

type TKlipyResponse = {
  data?: {
    data?: TKlipyItem[];
    pagination?: { page?: number; total_pages?: number };
  };
};

const mapItem = (item: TKlipyItem): TGif | undefined => {
  const preview = item.file?.sm?.gif ?? item.file?.md?.gif;
  const full = item.file?.md?.gif ?? item.file?.hd?.gif ?? preview;

  if (!preview?.url || !full?.url) return undefined;

  return {
    id: String(item.id),
    title: item.title ?? 'GIF',
    url: full.url,
    previewUrl: preview.url,
    width: full.width ?? preview.width ?? 1,
    height: full.height ?? preview.height ?? 1
  };
};

const fetchKlipyGifs = async (params: {
  apiKey: string;
  customerId: string;
  query?: string;
  page: number;
  perPage: number;
}): Promise<TGifPage> => {
  const endpoint = params.query ? 'search' : 'trending';
  const search = new URLSearchParams({
    customer_id: params.customerId,
    page: String(params.page),
    per_page: String(params.perPage),
    format_filter: 'gif'
  });

  if (params.query) {
    search.set('q', params.query);
  }

  const response = await fetch(
    `${KLIPY_BASE_URL}/${encodeURIComponent(params.apiKey)}/gifs/${endpoint}?${search.toString()}`
  );

  if (!response.ok) {
    throw new Error(`Klipy answered ${response.status}`);
  }

  const payload = (await response.json()) as TKlipyResponse;
  const gifs = (payload.data?.data ?? [])
    .map(mapItem)
    .filter((gif): gif is TGif => !!gif);
  const pagination = payload.data?.pagination;

  const hasMore = pagination?.total_pages
    ? (pagination.page ?? params.page) < pagination.total_pages
    : gifs.length >= params.perPage;

  return { gifs, hasMore };
};

export { fetchKlipyGifs, resolveKlipyApiKey };
