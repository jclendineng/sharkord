import {
  ActivityLogType,
  Permission,
  STICKER_DESCRIPTION_MAX_LENGTH,
  STICKER_NAME_MAX_LENGTH,
  STICKER_NAME_MIN_LENGTH
} from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { db } from '../../db';
import { publishSticker } from '../../db/publishers';
import { stickers } from '../../db/schema';
import { enqueueActivityLog } from '../../queues/activity-log';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

const updateStickerRoute = protectedProcedure
  .input(
    z.object({
      stickerId: z.number(),
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

    const existing = await db
      .select({ id: stickers.id, name: stickers.name })
      .from(stickers)
      .where(eq(stickers.id, input.stickerId))
      .limit(1)
      .get();

    invariant(existing, {
      code: 'NOT_FOUND',
      message: 'Sticker not found.'
    });

    await db
      .update(stickers)
      .set({
        name: input.name,
        description: input.description || null,
        updatedAt: Date.now()
      })
      .where(eq(stickers.id, existing.id));

    publishSticker(existing.id, 'update');
    enqueueActivityLog({
      type: ActivityLogType.UPDATED_STICKER,
      userId: ctx.user.id,
      details: { fromName: existing.name, toName: input.name }
    });
  });

export { updateStickerRoute };
