import { Permission, SOUNDBOARD_LIBRARY } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { soundboardSounds } from '../../db/schema';
import { createSound } from '../../helpers/create-sound';
import { fileManager } from '../../helpers/file-manager';
import { getSoundboardLibraryFile } from '../../helpers/soundboard-library';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const libraryKeys = SOUNDBOARD_LIBRARY.map(({ key }) => key) as [
  (typeof SOUNDBOARD_LIBRARY)[number]['key'],
  ...(typeof SOUNDBOARD_LIBRARY)[number]['key'][]
];

// a sound from the library the server ships with, copied into storage so it is a sound like
// any other from then on: renamed, turned down or deleted the same way
const addLibrarySoundRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.addEmoji.maxRequests,
  windowMs: config.rateLimiters.addEmoji.windowMs,
  logLabel: 'addLibrarySound'
})
  .input(z.object({ key: z.enum(libraryKeys) }))
  .mutation(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.MANAGE_SOUNDBOARD);

    const existing = await db
      .select({ id: soundboardSounds.id })
      .from(soundboardSounds)
      .where(eq(soundboardSounds.libraryKey, input.key))
      .limit(1)
      .get();

    invariant(!existing, {
      code: 'CONFLICT',
      message: 'This server already has that sound.'
    });

    const entry = SOUNDBOARD_LIBRARY.find(({ key }) => key === input.key);

    invariant(entry, { code: 'NOT_FOUND', message: 'Sound not found.' });

    const originalName = `${entry.key}.m4a`;
    const source = Bun.file(getSoundboardLibraryFile(entry.key));
    const stagingPath = await fileManager.getSafeUploadPath(originalName);
    const size = await Bun.write(stagingPath, source);
    const tempFile = await fileManager.addTemporaryFile({
      filePath: stagingPath,
      size,
      originalName,
      userId: ctx.userId
    });

    return createSound({
      tempFileId: tempFile.id,
      userId: ctx.userId,
      name: entry.name,
      emoji: entry.emoji,
      volume: 100,
      libraryKey: entry.key
    });
  });

export { addLibrarySoundRoute };
