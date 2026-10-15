import { eq } from 'drizzle-orm';
import http from 'http';
import z from 'zod';
import { config } from '../config';
import { db } from '../db';
import { users } from '../db/schema';
import { getWsInfo } from '../helpers/get-ws-info';
import {
  createLoginRequest,
  deleteLoginRequest,
  getLoginRequestByPollKey
} from '../helpers/login-requests';
import { createSessionToken } from '../helpers/sessions';
import { createRateLimiter } from '../utils/rate-limiters/rate-limiter';
import { HttpValidationError } from './errors';
import { enforceHttpRateLimit, getJsonBody } from './helpers';

const zBody = z.object({
  id: z.string().min(1).max(64).optional(),
  pollKey: z.string().min(1).max(200).optional()
});

const loginRequestRateLimiter = createRateLimiter({
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

// pre-auth on purpose: a device without a camera, with no session yet, asks to be signed in.
// called bare it starts a request and gets the token for its qr code and a poll key, called
// with the request's id and that key it learns whether a signed in device approved it, and
// collects the session once one has. the key never goes in the qr code, so whoever scans it
// can approve it but never collect it
const loginRequestRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse
) => {
  const data = zBody.parse(await getJsonBody(req));
  const info = getWsInfo(undefined, req);

  const allowed = enforceHttpRateLimit(res, loginRequestRateLimiter, info?.ip, {
    route: '/login/request',
    message: 'Too many attempts. Please try again shortly.'
  });

  if (!allowed) return;

  if (!data.id || !data.pollKey) {
    const request = await createLoginRequest({
      os: info?.os,
      device: info?.device,
      ip: info?.ip
    });

    sendJson(res, 201, request);

    return res;
  }

  const request = await getLoginRequestByPollKey(data.id, data.pollKey);

  if (!request || request.expiresAt < Date.now()) {
    throw new HttpValidationError(
      'id',
      'This sign in code has run out. Show a new one.'
    );
  }

  if (request.status === 'denied') {
    await deleteLoginRequest(request.id);

    throw new HttpValidationError(
      'id',
      'Sign in was declined on your other device.'
    );
  }

  if (request.status !== 'approved' || !request.userId) {
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
    .where(eq(users.id, request.userId))
    .limit(1)
    .get();

  await deleteLoginRequest(request.id);

  if (!user || user.banned) {
    throw new HttpValidationError('id', 'This account cannot sign in.');
  }

  const token = await createSessionToken(user.id, user.tokenVersion, info);

  sendJson(res, 200, { success: true, token });

  return res;
};

export { loginRequestRouteHandler };
