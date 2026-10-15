import { eq } from 'drizzle-orm';
import http from 'http';
import z from 'zod';
import { config } from '../config';
import { db } from '../db';
import { users } from '../db/schema';
import { getWsInfo } from '../helpers/get-ws-info';
import {
  claimLoginLink,
  deleteLoginLink,
  getLoginLinkByToken,
  matchesLoginLinkSecret
} from '../helpers/login-links';
import { createSessionToken } from '../helpers/sessions';
import { createRateLimiter } from '../utils/rate-limiters/rate-limiter';
import { HttpValidationError } from './errors';
import { enforceHttpRateLimit, getJsonBody } from './helpers';

const zBody = z.object({
  token: z.string().min(1).max(200),
  claimKey: z.string().min(1).max(200).optional()
});

const loginLinkRateLimiter = createRateLimiter({
  maxRequests: config.rateLimiters.loginLink.maxRequests,
  windowMs: config.rateLimiters.loginLink.windowMs
});

const sendJson = (
  res: http.ServerResponse,
  status: number,
  body: Record<string, unknown>
) => {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
};

// pre-auth on purpose: the device calling it has no session yet, that is what it is after. the
// first call with a qr code's token claims it and is handed a key, every later one must bring
// that key, so nobody else who saw the code can collect the session the owner approves
const loginLinkRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse
) => {
  const data = zBody.parse(await getJsonBody(req));
  const info = getWsInfo(undefined, req);

  const allowed = enforceHttpRateLimit(res, loginLinkRateLimiter, info?.ip, {
    route: '/login/link',
    message: 'Too many attempts. Please try again shortly.'
  });

  if (!allowed) return;

  const link = await getLoginLinkByToken(data.token);

  if (!link) {
    throw new HttpValidationError(
      'token',
      'This sign in code has run out. Show a new one on your other device.'
    );
  }

  if (link.status === 'waiting' && !data.claimKey) {
    const claimKey = await claimLoginLink(link.id, {
      os: info?.os,
      device: info?.device,
      ip: info?.ip
    });

    if (claimKey) {
      sendJson(res, 202, { status: 'pending', claimKey });

      return res;
    }
  }

  if (
    !data.claimKey ||
    !matchesLoginLinkSecret(data.claimKey, link.claimKeyHash)
  ) {
    throw new HttpValidationError(
      'token',
      'Another device already scanned this code. Show a new one.'
    );
  }

  if (link.status === 'denied') {
    await deleteLoginLink(link.id);

    throw new HttpValidationError(
      'token',
      'Sign in was declined on your other device.'
    );
  }

  if (link.status !== 'approved') {
    sendJson(res, 202, { status: 'pending' });

    return res;
  }

  const user = await db
    .select({
      id: users.id,
      banned: users.banned,
      tokenVersion: users.tokenVersion
    })
    .from(users)
    .where(eq(users.id, link.userId))
    .limit(1)
    .get();

  await deleteLoginLink(link.id);

  if (!user || user.banned) {
    throw new HttpValidationError('token', 'This account cannot sign in.');
  }

  const token = await createSessionToken(user.id, user.tokenVersion, info);

  sendJson(res, 200, { success: true, token });

  return res;
};

export { loginLinkRouteHandler };
