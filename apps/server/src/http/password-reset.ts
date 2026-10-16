import http from 'http';
import z from 'zod';
import { config } from '../config';
import { getWsInfo } from '../helpers/get-ws-info';
import { redeemPasswordReset } from '../helpers/password-resets';
import { createRateLimiter } from '../utils/rate-limiters/rate-limiter';
import { HttpValidationError } from './errors';
import { enforceHttpRateLimit, getJsonBody } from './helpers';

const zBody = z.object({
  token: z.string().min(1).max(200),
  password: z.string().min(4).max(128)
});

const passwordResetRateLimiter = createRateLimiter({
  maxRequests: config.rateLimiters.login.maxRequests,
  windowMs: config.rateLimiters.login.windowMs
});

// pre-auth on purpose: whoever forgot their password has no session, the link's token is
// the credential. the account then signs in with the new password as usual
const passwordResetRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse
) => {
  const data = zBody.parse(await getJsonBody(req));
  const info = getWsInfo(undefined, req);

  const allowed = enforceHttpRateLimit(
    res,
    passwordResetRateLimiter,
    info?.ip,
    {
      route: '/password-reset',
      message: 'Too many attempts. Please try again shortly.'
    }
  );

  if (!allowed) return;

  const reset = await redeemPasswordReset(data.token, data.password);

  if (!reset) {
    throw new HttpValidationError(
      'token',
      'This reset link has expired or was already used. Ask for a new one.'
    );
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ success: true }));
};

export { passwordResetRouteHandler };
