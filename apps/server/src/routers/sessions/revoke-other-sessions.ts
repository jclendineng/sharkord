import { config } from '../../config';
import { revokeOtherSessions } from '../../helpers/sessions';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// every device but the one asking. a token from before sessions existed has no row to keep,
// so it signs out every session there is and only survives itself until it expires
const revokeOtherSessionsRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.updatePassword.maxRequests,
  windowMs: config.rateLimiters.updatePassword.windowMs,
  logLabel: 'revokeOtherSessions'
}).mutation(async ({ ctx }) => {
  const revokedCount = await revokeOtherSessions(ctx.userId, ctx.sessionId);

  return { revokedCount };
});

export { revokeOtherSessionsRoute };
