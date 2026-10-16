import {
  Permission,
  REACTION_EMOJI_MAX_LENGTH,
  SOUND_DEFAULT_VOLUME,
  SOUND_EXTENSIONS,
  SOUND_MAX_FILE_SIZE,
  SOUND_MAX_VOLUME,
  SOUND_MIN_VOLUME,
  SOUND_NAME_MAX_LENGTH,
  SOUND_NAME_MIN_LENGTH
} from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { createSound } from '../../helpers/create-sound';
import { fileManager } from '../../helpers/file-manager';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// managed with the emoji and stickers' limits, they are all a server's expressions
const addSoundRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.addEmoji.maxRequests,
  windowMs: config.rateLimiters.addEmoji.windowMs,
  logLabel: 'addSound'
})
  .input(
    z.object({
      fileId: z.string(),
      name: z
        .string()
        .trim()
        .min(SOUND_NAME_MIN_LENGTH)
        .max(SOUND_NAME_MAX_LENGTH),
      emoji: z.string().trim().max(REACTION_EMOJI_MAX_LENGTH).optional(),
      volume: z
        .number()
        .int()
        .min(SOUND_MIN_VOLUME)
        .max(SOUND_MAX_VOLUME)
        .default(SOUND_DEFAULT_VOLUME)
    })
  )
  .mutation(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.MANAGE_SOUNDBOARD);

    const tempFile = fileManager.getTemporaryFile(input.fileId);

    invariant(tempFile && tempFile.userId === ctx.userId, {
      code: 'NOT_FOUND',
      message: 'That upload was not found, try adding the sound again.'
    });

    invariant(
      SOUND_EXTENSIONS.includes(tempFile.extension.toLowerCase()) &&
        tempFile.size <= SOUND_MAX_FILE_SIZE,
      {
        code: 'BAD_REQUEST',
        message: 'A sound has to be an MP3, WAV or M4A file of 512 KB or less.'
      }
    );

    return createSound({
      tempFileId: tempFile.id,
      userId: ctx.userId,
      name: input.name,
      emoji: input.emoji || null,
      volume: input.volume,
      libraryKey: null
    });
  });

export { addSoundRoute };
