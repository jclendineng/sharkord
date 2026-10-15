import { z } from 'zod';
import { config } from '../../config';
import {
  answerLoginRequest,
  getLoginRequestByToken
} from '../../helpers/login-requests';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// the scanning device lets the one showing the qr code in to its own account, or turns it away
const approveLoginRequestRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.revokeSession.maxRequests,
  windowMs: config.rateLimiters.revokeSession.windowMs,
  logLabel: 'approveLoginRequest'
})
  .input(z.object({ token: z.string().min(1).max(200), approve: z.boolean() }))
  .mutation(async ({ ctx, input }) => {
    const request = await getLoginRequestByToken(input.token);

    invariant(request, {
      code: 'NOT_FOUND',
      message: 'That sign in code is gone. Show a new one.'
    });

    invariant(request.expiresAt >= Date.now(), {
      code: 'BAD_REQUEST',
      message: 'That sign in code has run out. Show a new one.'
    });

    const isAnswered = await answerLoginRequest(
      request.id,
      ctx.userId,
      input.approve
    );

    invariant(isAnswered, {
      code: 'BAD_REQUEST',
      message: 'That sign in code was already answered.'
    });
  });

export { approveLoginRequestRoute };
