import { z } from 'zod';
import { config } from '../../config';
import { revokeSession } from '../../helpers/sessions';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const revokeSessionRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.revokeSession.maxRequests,
  windowMs: config.rateLimiters.revokeSession.windowMs,
  logLabel: 'revokeSession'
})
  .input(
    z.object({
      sessionId: z.string().min(1).max(64)
    })
  )
  .mutation(async ({ ctx, input }) => {
    // scoped to the caller, so someone else's session reads as missing
    const revoked = await revokeSession(ctx.userId, input.sessionId);

    invariant(revoked, {
      code: 'NOT_FOUND',
      message: 'That device is already signed out.'
    });
  });

export { revokeSessionRoute };
