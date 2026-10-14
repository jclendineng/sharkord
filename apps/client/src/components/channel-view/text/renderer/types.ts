import type { TFile, TMessageMetadata } from '@sharkord/shared';

export type TFoundMedia = {
  key: string;
  type: 'image' | 'video' | 'audio';
  url: string;
  // an attachment, whose link is drawn again once a signed one runs out
  file?: TFile;
};

export type TFoundOpenGraph = {
  key: string;
  url: string;
  hostname: string;
  title?: string;
  siteName?: string;
  description?: string;
  imageUrl?: string;
  faviconUrl?: string;
};

export type TMessageMetadataLike = Partial<TMessageMetadata> & {
  kind?: TMessageMetadata['kind'];
  mediaType?: string;
  url?: string;
  title?: string;
  siteName?: string;
  description?: string;
  images?: string[];
  favicons?: string[];
};
