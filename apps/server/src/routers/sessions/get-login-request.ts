import { z } from 'zod';
import { config } from '../../config';
import { getLoginRequestByToken } from '../../helpers/login-requests';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// what a scanned qr code asks for, shown before it is approved: the device asking and when
const getLoginRequestRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.revokeSession.maxRequests,
  windowMs: config.rateLimiters.revokeSession.windowMs,
  logLabel: 'getLoginRequest'
})
  .input(z.object({ token: z.string().min(1).max(200) }))
  .query(async ({ input }) => {
    const request = await getLoginRequestByToken(input.token);

    invariant(request, {
      code: 'NOT_FOUND',
      message: 'That sign in code is gone. Show a new one.'
    });

    return {
      os: request.requestOs,
      device: request.requestDevice,
      createdAt: request.createdAt,
      status: request.expiresAt < Date.now() ? 'expired' : request.status
    };
  });

export { getLoginRequestRoute };
