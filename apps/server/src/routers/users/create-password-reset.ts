import { Permission } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { users } from '../../db/schema';
import { assertCanActOnUser } from '../../helpers/assert-can-act-on-user';
import { createPasswordReset } from '../../helpers/password-resets';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// there is no email to send a reset to, so a moderator makes a one time link and passes it on
// however they reach the person. the token is only ever returned here
const createPasswordResetRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.adminCreate.maxRequests,
  windowMs: config.rateLimiters.adminCreate.windowMs,
  logLabel: 'createPasswordReset'
})
  .input(z.object({ userId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    await ctx.needsPermission(Permission.MANAGE_USERS);

    const user = await db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.id, input.userId))
      .limit(1)
      .get();

    invariant(user, {
      code: 'NOT_FOUND',
      message: 'User not found.'
    });

    await assertCanActOnUser(ctx.userId, input.userId);

    return createPasswordReset(input.userId, ctx.userId);
  });

export { createPasswordResetRoute };
