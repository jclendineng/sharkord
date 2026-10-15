import {
  audioExtensions,
  imageExtensions,
  removeCommandElements,
  removeEmojiElements,
  videoExtensions,
  type TGenericObject,
  type TMessageMediaMetadata,
  type TMessageOpenGraphMetadata
} from '@sharkord/shared';

// if it ends in a known media extension, we just assume it's a direct media link and skip the DNS resolution and metadata fetching
// there might be cases where this is not true, but it's a good heuristic to avoid unnecessary work
const getDirectMediaMetaFromUrl = (
  parsedUrl: URL
): {
  isDirectMediaLink: boolean;
  mediaType: 'image' | 'video' | 'audio' | 'none';
} => {
  try {
    const pathname = parsedUrl.pathname.toLowerCase();

    const isImage = imageExtensions.some((ext) => pathname.endsWith(ext));

    if (isImage) {
      return { isDirectMediaLink: true, mediaType: 'image' };
    }

    const isAudio = audioExtensions.some((ext) => pathname.endsWith(ext));

    if (isAudio) {
      return { isDirectMediaLink: true, mediaType: 'audio' };
    }

    const isVideo = videoExtensions.some((ext) => pathname.endsWith(ext));

    if (isVideo) {
      return { isDirectMediaLink: true, mediaType: 'video' };
    }
  } catch {
    // ignore
  }

  return { isDirectMediaLink: false, mediaType: 'none' };
};

const sanitizeContent = (content: string): string => {
  let cleanContent = content;

  // this will remove plugin commands AND emojis because they need to be ignored for metadata extraction
  cleanContent = removeCommandElements(cleanContent);
  cleanContent = removeEmojiElements(cleanContent);

  return cleanContent;
};

const normalizeOptionalString = (value: unknown): string | undefined => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();

  return trimmed.length > 0 ? trimmed : undefined;
};

const normalizeAbsoluteUrl = (
  baseUrl: string,
  value: unknown
): string | undefined => {
  const rawValue =
    typeof value === 'object' && value !== null && 'url' in value
      ? value.url
      : value;

  const candidate = normalizeOptionalString(rawValue);

  if (!candidate) {
    return undefined;
  }

  try {
    return new URL(candidate, baseUrl).toString();
  } catch {
    return undefined;
  }
};

const normalizeUrlList = (
  baseUrl: string,
  value: unknown
): string[] | undefined => {
  const rawValues = Array.isArray(value) ? value : value ? [value] : [];
  const normalizedValues = Array.from(
    new Set(
      rawValues
        .map((item) => normalizeAbsoluteUrl(baseUrl, item))
        .filter((item) => !!item)
    )
  ) as string[];

  return normalizedValues.length > 0 ? normalizedValues : undefined;
};

const createDirectMediaMetadata = (
  url: string,
  parsedUrl: URL,
  mediaType: TMessageMediaMetadata['mediaType']
): TMessageMediaMetadata => {
  return {
    kind: 'media',
    url,
    title: parsedUrl.pathname.split('/').pop() || url,
    description: '',
    mediaType
  };
};

const createOpenGraphMetadata = (
  preview: TGenericObject,
  url: string
): TMessageOpenGraphMetadata | undefined => {
  const title =
    normalizeOptionalString(preview.title) ??
    normalizeOptionalString(preview.ogTitle);

  const siteName =
    normalizeOptionalString(preview.siteName) ??
    normalizeOptionalString(preview.ogSiteName);

  const description =
    normalizeOptionalString(preview.description) ??
    normalizeOptionalString(preview.ogDescription);

  const mediaType =
    normalizeOptionalString(preview.mediaType) ??
    normalizeOptionalString(preview.ogType) ??
    'website';

  const images = normalizeUrlList(url, preview.images ?? preview.ogImage);
  const videos = normalizeUrlList(url, preview.videos ?? preview.ogVideo);
  const favicons = normalizeUrlList(url, preview.favicons ?? preview.favicon);

  const hasRenderableContent =
    !!title ||
    !!siteName ||
    !!description ||
    !!images?.length ||
    !!favicons?.length;

  if (!hasRenderableContent) {
    return undefined;
  }

  return {
    kind: 'open_graph',
    url,
    title,
    siteName,
    description,
    mediaType,
    images,
    videos,
    favicons
  };
};

// whether a page names its own preview picture. without one link-preview-js offers every image
// on the page instead, which is mostly logos and banners cut from the middle, so discord shows
// none and neither do we
const declaresPreviewImage = (html: string) =>
  /<meta[^>]+(?:property|name)\s*=\s*["'](?:og:image|og:image:url|og:image:secure_url|twitter:image|twitter:image:src)["']/i.test(
    html
  );

// a page's icons, the sharpest first: the home screen icon made for phones, then the largest of
// its declared sizes, then whatever else it had. a 16 pixel favicon stretched over a card is a blur
const rankFavicons = (html: string, pageUrl: string, found: string[]) => {
  const ranked: { href: string; score: number }[] = [];

  for (const [tag] of html.matchAll(/<link\b[^>]*>/gi)) {
    const rel =
      /\brel\s*=\s*["']([^"']+)["']/i.exec(tag)?.[1]?.toLowerCase() ?? '';
    const href = /\bhref\s*=\s*["']([^"']+)["']/i.exec(tag)?.[1];

    if (!href || !rel.includes('icon')) {
      continue;
    }

    const sizes = /\bsizes\s*=\s*["'](\d+)x\d+["']/i.exec(tag)?.[1];
    const size = sizes ? Number(sizes) : 0;
    const isTouchIcon = rel.includes('apple-touch-icon');

    ranked.push({
      href,
      score: (isTouchIcon ? 1000 : 0) + Math.max(size, isTouchIcon ? 180 : 0)
    });
  }

  const best = ranked
    .sort((a, b) => b.score - a.score)
    .map(({ href }) => normalizeAbsoluteUrl(pageUrl, href))
    .filter((href): href is string => !!href);

  return Array.from(new Set([...best, ...found]));
};

export {
  createDirectMediaMetadata,
  createOpenGraphMetadata,
  declaresPreviewImage,
  getDirectMediaMetaFromUrl,
  rankFavicons,
  sanitizeContent
};
