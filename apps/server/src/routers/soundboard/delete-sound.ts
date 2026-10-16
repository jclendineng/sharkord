import { ActivityLogType, Permission } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { db } from '../../db';
import { removeFile } from '../../db/mutations/files';
import { publishSound } from '../../db/publishers';
import { soundboardSounds } from '../../db/schema';
import { enqueueActivityLog } from '../../queues/activity-log';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

// a library sound deleted here can be picked from the library again
const deleteSoundRoute = protectedProcedure
  .input(z.object({ soundId: z.number() }))
  .mutation(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.MANAGE_SOUNDBOARD);

    const removed = await db
      .delete(soundboardSounds)
      .where(eq(soundboardSounds.id, input.soundId))
      .returning()
      .get();

    invariant(removed, {
      code: 'NOT_FOUND',
      message: 'Sound not found.'
    });

    await removeFile(removed.fileId);

    publishSound(removed.id, 'delete');
    enqueueActivityLog({
      type: ActivityLogType.DELETED_SOUND,
      userId: ctx.user.id,
      details: { name: removed.name }
    });
  });

export { deleteSoundRoute };
