import { ActivityLogType, Permission } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { db } from '../../db';
import { removeFile } from '../../db/mutations/files';
import { publishSticker } from '../../db/publishers';
import { stickers } from '../../db/schema';
import { enqueueActivityLog } from '../../queues/activity-log';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

// messages that showed it keep their place and show the sticker as gone, the foreign key
// clears their reference
const deleteStickerRoute = protectedProcedure
  .input(z.object({ stickerId: z.number() }))
  .mutation(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.MANAGE_EMOJIS);

    const removed = await db
      .delete(stickers)
      .where(eq(stickers.id, input.stickerId))
      .returning()
      .get();

    invariant(removed, {
      code: 'NOT_FOUND',
      message: 'Sticker not found.'
    });

    await removeFile(removed.fileId);

    publishSticker(removed.id, 'delete');
    enqueueActivityLog({
      type: ActivityLogType.DELETED_STICKER,
      userId: ctx.user.id,
      details: { name: removed.name }
    });
  });

export { deleteStickerRoute };
