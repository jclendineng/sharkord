import {
  FREESOUND_MAX_DURATION_SECONDS,
  type TFreesoundPage,
  type TFreesoundSound
} from '@sharkord/shared';

// freesound, the cc licensed sound library. the key stays on the server and only managers
// search, through it. results are held to licenses that allow reuse anywhere: cc0, and cc by
// with its credit kept on the sound
const FREESOUND_BASE_URL = 'https://freesound.org/apiv2';
const FIELDS = 'id,name,username,license,duration,previews';
const LICENSE_FILTER =
  '(license:"Creative Commons 0" OR license:"Attribution")';

type TFreesoundItem = {
  id: number;
  name?: string;
  username?: string;
  license?: string;
  duration?: number;
  previews?: Record<string, string | undefined>;
};

type TFreesoundSearchResponse = {
  next?: string | null;
  results?: TFreesoundItem[];
};

// freesound names a license by its creative commons address
const toLicense = (
  url: string | undefined
): TFreesoundSound['license'] | undefined => {
  if (!url) return undefined;

  if (url.includes('/publicdomain/zero/')) return 'CC0';

  if (/\/licenses\/by\/\d/.test(url)) return 'CC BY';

  return undefined;
};

const mapItem = (item: TFreesoundItem): TFreesoundSound | undefined => {
  const license = toLicense(item.license);
  const previewUrl =
    item.previews?.['preview-hq-mp3'] ?? item.previews?.['preview-lq-mp3'];

  if (!license || !previewUrl || !item.name || !item.username) return undefined;

  return {
    id: item.id,
    name: item.name.replace(/\.(wav|mp3|ogg|flac|aiff?|m4a)$/i, ''),
    username: item.username,
    license,
    duration: item.duration ?? 0,
    previewUrl
  };
};

const fetchFreesound = async (
  apiKey: string,
  path: string,
  params: URLSearchParams
) => {
  params.set('fields', FIELDS);

  const response = await fetch(
    `${FREESOUND_BASE_URL}${path}?${params.toString()}`,
    {
      headers: { Authorization: `Token ${apiKey}` }
    }
  );

  if (!response.ok) {
    throw new Error(`Freesound answered ${response.status}`);
  }

  return response.json();
};

const searchFreesound = async (params: {
  apiKey: string;
  query: string;
  page: number;
  pageSize: number;
}): Promise<TFreesoundPage> => {
  const search = new URLSearchParams({
    query: params.query,
    page: String(params.page),
    page_size: String(params.pageSize),
    filter: `duration:[0 TO ${FREESOUND_MAX_DURATION_SECONDS}] ${LICENSE_FILTER}`
  });

  const payload = (await fetchFreesound(
    params.apiKey,
    '/search/text/',
    search
  )) as TFreesoundSearchResponse;

  const sounds = (payload.results ?? [])
    .map(mapItem)
    .filter((sound): sound is TFreesoundSound => !!sound);

  return { sounds, hasMore: !!payload.next };
};

// one sound by its id, checked again on the server rather than trusted from a search result
const getFreesoundSound = async (
  apiKey: string,
  id: number
): Promise<TFreesoundSound | undefined> => {
  const item = (await fetchFreesound(
    apiKey,
    `/sounds/${id}/`,
    new URLSearchParams()
  )) as TFreesoundItem;

  return mapItem(item);
};

export { getFreesoundSound, searchFreesound };
