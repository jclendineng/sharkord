import { config } from '../../config';
import { startTwoFactorSetup } from '../../helpers/two-factor';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// hands out the secret for the authenticator app, nothing is on until a code confirms it
const startTwoFactorRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.updatePassword.maxRequests,
  windowMs: config.rateLimiters.updatePassword.windowMs,
  logLabel: 'startTwoFactor'
}).mutation(async ({ ctx }) => startTwoFactorSetup(ctx.userId));

export { startTwoFactorRoute };
