import {
  FREESOUND_MAX_DURATION_SECONDS,
  SOUND_ATTRIBUTION_MAX_LENGTH,
  SOUND_MAX_FILE_SIZE,
  SOUND_NAME_MAX_LENGTH,
  SOUND_NAME_MIN_LENGTH,
  type TFreesoundPage
} from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import fs from 'fs/promises';
import { db } from '../db';
import { getSettings } from '../db/queries/server';
import { soundboardSounds } from '../db/schema';
import { getFreesoundSound, searchFreesound } from '../utils/freesound';
import { invariant } from '../utils/invariant';
import { readBodyWithLimit } from '../utils/read-body-with-limit';
import { createSound } from './create-sound';
import { fileManager } from './file-manager';

const PAGE_SIZE = 20;

const PROVIDER_ERROR = {
  code: 'BAD_GATEWAY',
  message: "Couldn't reach Freesound, try again in a moment."
} as const;

const asProviderError = (): never => {
  invariant(false, PROVIDER_ERROR);
};

const getFreesoundKey = async () => {
  const { freesoundApiKey } = await getSettings();

  invariant(freesoundApiKey, {
    code: 'PRECONDITION_FAILED',
    message: "Sound search isn't set up on this server."
  });

  return freesoundApiKey;
};

const searchFreesoundSounds = async (
  query: string,
  page: number
): Promise<TFreesoundPage> => {
  const apiKey = await getFreesoundKey();

  return searchFreesound({ apiKey, query, page, pageSize: PAGE_SIZE }).catch(
    asProviderError
  );
};

// a name a sound can keep: freesound's titles run long, and a short one is padded
const toSoundName = (title: string) => {
  const trimmed = title.trim();
  const padded =
    trimmed.length >= SOUND_NAME_MIN_LENGTH ? trimmed : `${trimmed} sound`;

  return padded.slice(0, SOUND_NAME_MAX_LENGTH).trim();
};

// only from freesound's own servers, so a changed answer cannot send the server elsewhere
const isFreesoundUrl = (url: string) => {
  try {
    const { protocol, hostname } = new URL(url);

    return (
      protocol === 'https:' &&
      (hostname === 'freesound.org' || hostname.endsWith('.freesound.org'))
    );
  } catch {
    return false;
  }
};

// the sound is looked up again by its id rather than trusted from the search, then its mp3
// preview is downloaded into storage like an upload, with its credit kept on it
const addFreesoundSound = async (freesoundId: number, userId: number) => {
  const apiKey = await getFreesoundKey();
  const sourceKey = `freesound:${freesoundId}`;

  const existing = await db
    .select({ id: soundboardSounds.id })
    .from(soundboardSounds)
    .where(eq(soundboardSounds.libraryKey, sourceKey))
    .limit(1)
    .get();

  invariant(!existing, {
    code: 'CONFLICT',
    message: 'This server already has that sound.'
  });

  const sound = await getFreesoundSound(apiKey, freesoundId).catch(
    asProviderError
  );

  invariant(sound && isFreesoundUrl(sound.previewUrl), {
    code: 'NOT_FOUND',
    message: "That sound isn't available to add."
  });

  invariant(sound.duration <= FREESOUND_MAX_DURATION_SECONDS, {
    code: 'BAD_REQUEST',
    message: `A sound can be ${FREESOUND_MAX_DURATION_SECONDS} seconds at most.`
  });

  const response = await fetch(sound.previewUrl).catch(asProviderError);

  invariant(response.ok, PROVIDER_ERROR);

  const originalName = `freesound-${sound.id}.mp3`;
  const stagingPath = await fileManager.getSafeUploadPath(originalName);
  const chunks: Uint8Array[] = [];

  try {
    await readBodyWithLimit(response, {
      maxBytes: SOUND_MAX_FILE_SIZE,
      tooLargeMessage: 'too large',
      onChunk: (chunk) => chunks.push(chunk)
    });
  } catch {
    invariant(false, {
      code: 'BAD_REQUEST',
      message: 'That sound is over 512 KB, the most a sound can be.'
    });
  }

  const bytes = Buffer.concat(chunks);

  await fs.writeFile(stagingPath, bytes);

  const tempFile = await fileManager.addTemporaryFile({
    filePath: stagingPath,
    size: bytes.byteLength,
    originalName,
    userId
  });

  const attribution =
    `"${sound.name}" by ${sound.username} on Freesound, ${sound.license}`.slice(
      0,
      SOUND_ATTRIBUTION_MAX_LENGTH
    );

  return createSound({
    tempFileId: tempFile.id,
    userId,
    name: toSoundName(sound.name),
    emoji: null,
    volume: 100,
    libraryKey: sourceKey,
    attribution
  });
};

export { addFreesoundSound, searchFreesoundSounds };
