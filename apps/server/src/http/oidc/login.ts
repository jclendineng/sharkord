import { getErrorMessage, OidcError } from '@sharkord/shared';
import type http from 'http';
import * as client from 'openid-client';
import type { getWsInfo } from '../../helpers/get-ws-info';
import { zInviteCode } from '../../helpers/invites';
import {
  oidcManager,
  TRANSACTION_TTL_SECONDS
} from '../../helpers/oidc/manager';
import { logger } from '../../logger';
import {
  buildStateCookie,
  guardOidcRoute,
  redirectWithError,
  zAppChallenge
} from './common';

const oidcLoginRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse,
  { info, url }: { info: ReturnType<typeof getWsInfo>; url: URL }
) => {
  const guarded = guardOidcRoute(req, res, {
    ip: info?.ip,
    route: '/oidc/login',
    isNavigation: true
  });

  if (!guarded) return;

  const appChallenge = url.searchParams.get('app_challenge');

  if (appChallenge !== null && !zAppChallenge.safeParse(appChallenge).success) {
    redirectWithError(req, res, OidcError.SERVER_ERROR);

    return;
  }

  // an invite lets a new account in through sso the way it does for a password sign up. one
  // that is malformed is dropped, the sign in then goes on as if it had none
  const parsedInvite = zInviteCode.safeParse(url.searchParams.get('invite'));
  const inviteCode = parsedInvite.success ? parsedInvite.data : null;

  try {
    const oidcConfig = await oidcManager.getConfiguration();

    const state = client.randomState();
    const nonce = client.randomNonce();
    const codeVerifier = client.randomPKCECodeVerifier();
    const codeChallenge = await client.calculatePKCECodeChallenge(codeVerifier);
    const redirectUri = oidcManager.resolveRedirectUri(req);

    oidcManager.startTransaction(state, {
      nonce,
      codeVerifier,
      redirectUri,
      appChallenge,
      inviteCode
    });

    const authorizationUrl = client.buildAuthorizationUrl(oidcConfig, {
      redirect_uri: redirectUri,
      scope: 'openid profile email',
      code_challenge: codeChallenge,
      code_challenge_method: 'S256',
      state,
      nonce
    });

    res.writeHead(302, {
      'Cache-Control': 'no-store',
      'Set-Cookie': buildStateCookie(req, state, TRANSACTION_TTL_SECONDS),
      Location: authorizationUrl.href
    });
    res.end();
  } catch (error) {
    logger.error('OIDC login failed to start: %s', getErrorMessage(error));

    redirectWithError(req, res, OidcError.SERVER_ERROR);
  }
};

export { oidcLoginRouteHandler };
