import {
  ActivityLogType,
  FileSaveType,
  Permission,
  STICKER_DESCRIPTION_MAX_LENGTH,
  STICKER_EXTENSIONS,
  STICKER_MAX_FILE_SIZE,
  STICKER_NAME_MAX_LENGTH,
  STICKER_NAME_MIN_LENGTH
} from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { publishSticker } from '../../db/publishers';
import { stickers } from '../../db/schema';
import { fileManager } from '../../helpers/file-manager';
import { enqueueActivityLog } from '../../queues/activity-log';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// stickers are managed with the emoji, as discord keeps them together as expressions
const addStickerRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.addEmoji.maxRequests,
  windowMs: config.rateLimiters.addEmoji.windowMs,
  logLabel: 'addSticker'
})
  .input(
    z.object({
      fileId: z.string(),
      name: z
        .string()
        .trim()
        .min(STICKER_NAME_MIN_LENGTH)
        .max(STICKER_NAME_MAX_LENGTH),
      description: z
        .string()
        .trim()
        .max(STICKER_DESCRIPTION_MAX_LENGTH)
        .optional()
    })
  )
  .mutation(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.MANAGE_EMOJIS);

    const tempFile = fileManager.getTemporaryFile(input.fileId);

    invariant(tempFile && tempFile.userId === ctx.userId, {
      code: 'NOT_FOUND',
      message: 'That upload was not found, try adding the sticker again.'
    });

    invariant(
      STICKER_EXTENSIONS.includes(tempFile.extension.toLowerCase()) &&
        tempFile.size <= STICKER_MAX_FILE_SIZE,
      {
        code: 'BAD_REQUEST',
        message:
          'A sticker has to be a PNG, APNG, GIF or WebP image of 512 KB or less.'
      }
    );

    const file = await fileManager.saveFile(
      input.fileId,
      ctx.userId,
      FileSaveType.STICKER
    );

    const sticker = await db
      .insert(stickers)
      .values({
        name: input.name,
        description: input.description || null,
        fileId: file.id,
        userId: ctx.userId,
        createdAt: Date.now()
      })
      .returning()
      .get();

    publishSticker(sticker.id, 'create');
    enqueueActivityLog({
      type: ActivityLogType.CREATED_STICKER,
      userId: ctx.user.id,
      details: { name: sticker.name }
    });

    return sticker.id;
  });

export { addStickerRoute };
