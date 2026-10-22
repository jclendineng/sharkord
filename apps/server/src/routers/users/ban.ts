import { Permission } from '@sharkord/shared';
import z from 'zod';
import { assertCanActOnUser } from '../../helpers/assert-can-act-on-user';
import { banUser, ctxUserSessions } from '../../helpers/moderation';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

const banRoute = protectedProcedure
  .input(
    z.object({
      userId: z.number(),
      reason: z.string().optional(),
      // a choice per ban: a shared household or office would lose access with it
      banIps: z.boolean().default(false)
    })
  )
  .mutation(async ({ ctx, input }) => {
    await ctx.needsPermission(Permission.BAN_MEMBERS);

    invariant(input.userId !== ctx.user.id, {
      code: 'BAD_REQUEST',
      message: 'You cannot ban yourself.'
    });

    await assertCanActOnUser(ctx.userId, input.userId);

    await banUser(
      input.userId,
      input.reason,
      ctx.userId,
      ctxUserSessions(ctx, input.userId),
      { banIps: input.banIps }
    );
  });

export { banRoute };
