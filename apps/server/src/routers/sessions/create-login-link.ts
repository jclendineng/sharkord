import { config } from '../../config';
import { createLoginLink } from '../../helpers/login-links';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// a qr code for signing another device in, shown by one already signed in
const createLoginLinkRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.revokeSession.maxRequests,
  windowMs: config.rateLimiters.revokeSession.windowMs,
  logLabel: 'createLoginLink'
}).mutation(async ({ ctx }) => createLoginLink(ctx.userId));

export { createLoginLinkRoute };
