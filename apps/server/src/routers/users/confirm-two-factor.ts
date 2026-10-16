import { z } from 'zod';
import { config } from '../../config';
import { confirmTwoFactorSetup } from '../../helpers/two-factor';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const confirmTwoFactorRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.updatePassword.maxRequests,
  windowMs: config.rateLimiters.updatePassword.windowMs,
  logLabel: 'confirmTwoFactor'
})
  .input(z.object({ code: z.string().trim().min(6).max(12) }))
  .mutation(async ({ ctx, input }) => ({
    recoveryCodes: await confirmTwoFactorSetup(ctx.userId, input.code)
  }));

export { confirmTwoFactorRoute };
