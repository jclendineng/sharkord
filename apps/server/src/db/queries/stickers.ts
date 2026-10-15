import type { TJoinedSticker } from '@sharkord/shared';
import { eq, inArray } from 'drizzle-orm';
import { db } from '..';
import { attachFileToken } from '../../helpers/files-crypto';
import { files, stickers } from '../schema';
import { getSettings } from './server';

const getStickerRows = () =>
  db
    .select({ sticker: stickers, file: files })
    .from(stickers)
    .innerJoin(files, eq(stickers.fileId, files.id));

type TStickerRow = Awaited<ReturnType<typeof getStickerRows>>[number];

const parseSticker = (
  row: TStickerRow,
  signedUrlsTtlSeconds: number
): TJoinedSticker => ({
  ...row.sticker,
  file: attachFileToken(row.file, signedUrlsTtlSeconds)
});

const getStickers = async (): Promise<TJoinedSticker[]> => {
  const [rows, { storageSignedUrlsTtlSeconds }] = await Promise.all([
    getStickerRows().orderBy(stickers.createdAt),
    getSettings()
  ]);

  return rows.map((row) => parseSticker(row, storageSignedUrlsTtlSeconds));
};

const getStickerById = async (
  id: number
): Promise<TJoinedSticker | undefined> => {
  const row = await getStickerRows().where(eq(stickers.id, id)).limit(1).get();

  if (!row) return undefined;

  const { storageSignedUrlsTtlSeconds } = await getSettings();

  return parseSticker(row, storageSignedUrlsTtlSeconds);
};

// the stickers a page of messages shows, one query whatever its size
const getStickersByIds = async (
  ids: number[]
): Promise<Map<number, TJoinedSticker>> => {
  const result = new Map<number, TJoinedSticker>();

  if (ids.length === 0) return result;

  const [rows, { storageSignedUrlsTtlSeconds }] = await Promise.all([
    getStickerRows().where(inArray(stickers.id, ids)),
    getSettings()
  ]);

  for (const row of rows) {
    result.set(row.sticker.id, parseSticker(row, storageSignedUrlsTtlSeconds));
  }

  return result;
};

export { getStickerById, getStickers, getStickersByIds };
