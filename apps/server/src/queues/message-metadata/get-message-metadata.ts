import { extractUrls, type TMessageMetadata } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { getPreviewFromContent } from 'link-preview-js';
import { isIP } from 'net';
import { db } from '../../db';
import { getSettings } from '../../db/queries/server';
import { messages } from '../../db/schema';
import { isPrivateIP } from '../../helpers/network';
import { fetchPage } from './fetch-page';
import {
  createDirectMediaMetadata,
  createOpenGraphMetadata,
  declaresPreviewImage,
  getDirectMediaMetaFromUrl,
  sanitizeContent
} from './helpers';

const metadataCache = new Map<string, TMessageMetadata | undefined>();

setInterval(
  () => metadataCache.clear(),
  1000 * 60 * 60 * 2 // clear cache every 2 hours
);

const urlMetadataParser = async (
  content: string
): Promise<TMessageMetadata[]> => {
  try {
    const cleanContent = sanitizeContent(content);
    const urls = extractUrls(cleanContent);

    if (!urls) return [];

    // a server on a home network may preview its own links, when the admin allows it
    const { linkPreviewsPrivateNetwork } = await getSettings();
    const isBlockedAddress = (address: string) =>
      !linkPreviewsPrivateNetwork && isPrivateIP(address);

    const promises = urls.map(async (url) => {
      if (metadataCache.has(url)) return metadataCache.get(url);

      if (!URL.canParse(url)) {
        return;
      }

      const parsed = new URL(url);

      const isEmojiImage =
        parsed.hostname === 'cdn.jsdelivr.net' &&
        parsed.pathname.includes('emoji-datasource');

      // it's a tiptap emoji, ignore
      if (isEmojiImage) return;

      // allow only http and https protocols
      if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
        return;
      }

      // it's already an ip address, check if it's private
      if (isIP(parsed.hostname) && isBlockedAddress(parsed.hostname)) {
        return;
      }

      // if the URL has a known media extension, skip getLinkPreview entirely and use extension-based detection
      const { isDirectMediaLink, mediaType } =
        getDirectMediaMetaFromUrl(parsed);

      if (isDirectMediaLink && mediaType !== 'none') {
        const directMetadata = createDirectMediaMetadata(
          url,
          parsed,
          mediaType
        );

        metadataCache.set(url, directMetadata);

        return directMetadata;
      }

      let metadata;

      try {
        const page = await fetchPage(url, isBlockedAddress);

        if (page) {
          metadata = await getPreviewFromContent(page);

          if (
            page.data &&
            !declaresPreviewImage(page.data) &&
            'images' in metadata
          ) {
            metadata = { ...metadata, images: [] };
          }
        }
      } catch {
        // unreachable, refused, timed out or not a page
      }

      if (!metadata) return;

      const normalizedMetadata = createOpenGraphMetadata(metadata, url);

      metadataCache.set(url, normalizedMetadata);

      return normalizedMetadata;
    });

    const metadata = await Promise.all(promises);
    const validMetadata = (metadata ?? []).filter((item) => !!item);

    return validMetadata;
  } catch {
    // ignore
  }

  return [];
};

export const processMessageMetadata = async (
  content: string,
  messageId: number
) => {
  const metadata = await urlMetadataParser(content);

  const hasMetadata = metadata && metadata.length > 0;

  if (!hasMetadata) return;

  return db
    .update(messages)
    .set({
      metadata,
      updatedAt: Date.now()
    })
    .where(eq(messages.id, messageId))
    .returning()
    .get();
};
