import { ActivityLogType, Permission } from '@sharkord/shared';
import { and, eq, isNull } from 'drizzle-orm';
import { z } from 'zod';
import { db } from '../../db';
import { invites } from '../../db/schema';
import { enqueueActivityLog } from '../../queues/activity-log';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

const deleteInviteRoute = protectedProcedure
  .input(
    z.object({
      inviteId: z.number()
    })
  )
  .mutation(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.MANAGE_INVITES);

    // marked rather than removed, so the list keeps who joined with it
    const removedInvite = await db
      .update(invites)
      .set({ deletedAt: Date.now() })
      .where(and(eq(invites.id, input.inviteId), isNull(invites.deletedAt)))
      .returning()
      .get();

    invariant(removedInvite, {
      code: 'NOT_FOUND',
      message: 'Invite not found'
    });

    enqueueActivityLog({
      type: ActivityLogType.DELETED_INVITE,
      userId: ctx.user.id,
      details: {
        code: removedInvite.code
      }
    });
  });

export { deleteInviteRoute };
