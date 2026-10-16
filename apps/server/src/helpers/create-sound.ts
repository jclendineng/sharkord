import { ActivityLogType, FileSaveType } from '@sharkord/shared';
import { db } from '../db';
import { publishSound } from '../db/publishers';
import { soundboardSounds } from '../db/schema';
import { enqueueActivityLog } from '../queues/activity-log';
import { fileManager } from './file-manager';

type TCreateSound = {
  tempFileId: string;
  userId: number;
  name: string;
  emoji: string | null;
  volume: number;
  libraryKey: string | null;
};

// an upload and a sound picked from the library end the same way: the file saved, the row,
// the event and the log
const createSound = async ({
  tempFileId,
  userId,
  name,
  emoji,
  volume,
  libraryKey
}: TCreateSound) => {
  const file = await fileManager.saveFile(
    tempFileId,
    userId,
    FileSaveType.SOUND
  );

  const sound = await db
    .insert(soundboardSounds)
    .values({
      name,
      emoji,
      volume,
      libraryKey,
      fileId: file.id,
      userId,
      createdAt: Date.now()
    })
    .returning()
    .get();

  publishSound(sound.id, 'create');
  enqueueActivityLog({
    type: ActivityLogType.CREATED_SOUND,
    userId,
    details: { name: sound.name }
  });

  return sound.id;
};

export { createSound };
