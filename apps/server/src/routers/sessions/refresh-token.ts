import { config } from '../../config';
import { createSessionToken, signSessionToken } from '../../helpers/sessions';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// a fresh token for the same session, which moves a token that still carries an expiry onto
// one without. a token from before sessions existed is moved onto a session of its own
const refreshTokenRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.joinServer.maxRequests,
  windowMs: config.rateLimiters.joinServer.windowMs,
  logLabel: 'refreshToken'
}).mutation(async ({ ctx }) => {
  const { id, tokenVersion } = ctx.user;

  const token = ctx.sessionId
    ? await signSessionToken(id, tokenVersion, ctx.sessionId)
    : await createSessionToken(id, tokenVersion, ctx.getConnectionInfo());

  return { token };
});

export { refreshTokenRoute };
