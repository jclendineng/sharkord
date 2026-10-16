import type { TJoinedSoundboardSound } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { db } from '..';
import { attachFileToken } from '../../helpers/files-crypto';
import { files, soundboardSounds } from '../schema';
import { getSettings } from './server';

const getSoundRows = () =>
  db
    .select({ sound: soundboardSounds, file: files })
    .from(soundboardSounds)
    .innerJoin(files, eq(soundboardSounds.fileId, files.id));

type TSoundRow = Awaited<ReturnType<typeof getSoundRows>>[number];

const parseSound = (
  row: TSoundRow,
  signedUrlsTtlSeconds: number
): TJoinedSoundboardSound => ({
  ...row.sound,
  file: attachFileToken(row.file, signedUrlsTtlSeconds)
});

// a soundboard is a few dozen sounds at most, so it is loaded whole like the emoji
const getSounds = async (): Promise<TJoinedSoundboardSound[]> => {
  const [rows, { storageSignedUrlsTtlSeconds }] = await Promise.all([
    getSoundRows().orderBy(soundboardSounds.createdAt),
    getSettings()
  ]);

  return rows.map((row) => parseSound(row, storageSignedUrlsTtlSeconds));
};

const getSoundById = async (
  id: number
): Promise<TJoinedSoundboardSound | undefined> => {
  const row = await getSoundRows()
    .where(eq(soundboardSounds.id, id))
    .limit(1)
    .get();

  if (!row) return undefined;

  const { storageSignedUrlsTtlSeconds } = await getSettings();

  return parseSound(row, storageSignedUrlsTtlSeconds);
};

export { getSoundById, getSounds };
