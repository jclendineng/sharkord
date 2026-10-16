import { z } from 'zod';
import { config } from '../../config';
import { disableTwoFactor } from '../../helpers/two-factor';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const disableTwoFactorRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.updatePassword.maxRequests,
  windowMs: config.rateLimiters.updatePassword.windowMs,
  logLabel: 'disableTwoFactor'
})
  .input(z.object({ code: z.string().trim().min(6).max(12) }))
  .mutation(async ({ ctx, input }) => {
    await disableTwoFactor(ctx.userId, input.code);
  });

export { disableTwoFactorRoute };
