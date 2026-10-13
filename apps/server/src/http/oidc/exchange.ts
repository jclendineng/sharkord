import { createHash } from 'crypto';
import type http from 'http';
import z from 'zod';
import type { getWsInfo } from '../../helpers/get-ws-info';
import { oidcManager } from '../../helpers/oidc/manager';
import { getJsonBody, sendJsonError } from '../helpers';
import { clearStateCookie, guardOidcRoute, hasStateCookie } from './common';

const zBody = z.object({
  code: z.string().min(1).max(256),
  // pkce allows 43 to 128 characters for a verifier
  verifier: z.string().min(43).max(128).optional()
});

const oidcExchangeRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse,
  { info }: { info: ReturnType<typeof getWsInfo> }
) => {
  const guarded = guardOidcRoute(req, res, {
    ip: info?.ip,
    route: '/oidc/exchange',
    isNavigation: false
  });

  if (!guarded) return;

  const data = zBody.parse(await getJsonBody(req));
  const handoff = oidcManager.takeHandoff(data.code);

  // the state cookie lives in the browser an app signs in through, never in the app itself,
  // so an app proves it started the login with the verifier behind its challenge instead
  let isBound = false;

  if (handoff?.appChallenge) {
    isBound =
      !!data.verifier &&
      createHash('sha256').update(data.verifier).digest('base64url') ===
        handoff.appChallenge;
  } else if (handoff) {
    isBound = hasStateCookie(req, handoff.state);
  }

  if (!handoff || !isBound) {
    sendJsonError(res, 401, 'This sign in link has expired, please try again');

    return;
  }

  res.writeHead(200, {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
    ...(handoff.appChallenge
      ? {}
      : { 'Set-Cookie': clearStateCookie(req, handoff.state) })
  });
  res.end(JSON.stringify({ success: true, token: handoff.token }));
};

export { oidcExchangeRouteHandler };
