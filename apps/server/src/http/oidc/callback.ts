import { getErrorMessage, OidcError } from '@sharkord/shared';
import type http from 'http';
import * as client from 'openid-client';
import type { getWsInfo } from '../../helpers/get-ws-info';
import { OidcCallbackError } from '../../helpers/oidc/error';
import { oidcManager } from '../../helpers/oidc/manager';
import { resolveOidcUser, type TOidcClaims } from '../../helpers/oidc/user';
import { createSessionToken } from '../../helpers/sessions';
import { logger } from '../../logger';
import type { TConnectionInfo } from '../../types';
import {
  clearStateCookie,
  guardOidcRoute,
  hasStateCookie,
  OIDC_APP_REDIRECT,
  redirectWithError
} from './common';

const collectClaims = async (
  oidcConfig: client.Configuration,
  tokens: client.TokenEndpointResponse & client.TokenEndpointResponseHelpers
): Promise<{ claims: TOidcClaims; userInfoFailed: boolean }> => {
  const idTokenClaims = tokens.claims();

  if (!idTokenClaims?.sub) {
    throw new OidcCallbackError(
      OidcError.SERVER_ERROR,
      'ID token is missing the sub claim'
    );
  }

  const needsUserInfo =
    !idTokenClaims.email ||
    !idTokenClaims.preferred_username ||
    !idTokenClaims.picture;

  if (!needsUserInfo) {
    return { claims: { ...idTokenClaims }, userInfoFailed: false };
  }

  try {
    const userInfo = await client.fetchUserInfo(
      oidcConfig,
      tokens.access_token,
      idTokenClaims.sub
    );

    return { claims: { ...userInfo, ...idTokenClaims }, userInfoFailed: false };
  } catch (error) {
    logger.warn(
      'OIDC userinfo request failed, continuing with ID token claims only: %s',
      getErrorMessage(error)
    );

    return { claims: { ...idTokenClaims }, userInfoFailed: true };
  }
};

type TOidcTransaction = NonNullable<
  ReturnType<typeof oidcManager.takeTransaction>
>;

const takeCallbackTransaction = (
  req: http.IncomingMessage,
  stateParam: string | null
): TOidcTransaction => {
  if (!stateParam || !hasStateCookie(req, stateParam)) {
    throw new OidcCallbackError(
      OidcError.INVALID_STATE,
      'No state cookie for the state this callback carries'
    );
  }

  const transaction = oidcManager.takeTransaction(stateParam);

  if (!transaction) {
    throw new OidcCallbackError(
      OidcError.EXPIRED,
      'No pending login for this state, it expired or was already used'
    );
  }

  return transaction;
};

const completeOidcCallback = async (
  transaction: TOidcTransaction,
  url: URL,
  info: TConnectionInfo | undefined
): Promise<{ handoffCode: string; origin: string }> => {
  if (url.searchParams.has('error')) {
    throw new OidcCallbackError(
      OidcError.ACCESS_DENIED,
      `Provider returned "${url.searchParams.get('error')}"`
    );
  }

  const oidcConfig = await oidcManager.getConfiguration();

  const callbackUrl = new URL(transaction.redirectUri);

  callbackUrl.search = url.search;

  const tokens = await client.authorizationCodeGrant(oidcConfig, callbackUrl, {
    pkceCodeVerifier: transaction.codeVerifier,
    expectedState: transaction.state,
    expectedNonce: transaction.nonce
  });

  const { claims, userInfoFailed } = await collectClaims(oidcConfig, tokens);
  const { user } = await resolveOidcUser(claims, {
    userInfoFailed,
    ip: info?.ip,
    inviteCode: transaction.inviteCode ?? undefined
  });

  if (user.banned) {
    throw new OidcCallbackError(
      OidcError.ACCESS_DENIED,
      `Banned user "${user.identity}" attempted to sign in through OIDC`
    );
  }

  // tokenVersion has to travel with the token, otherwise a kick or a password change no
  // longer invalidates the session and anyone already bumped can never sign in again
  const token = await createSessionToken(user.id, user.tokenVersion, info);

  return {
    handoffCode: oidcManager.createHandoff(
      token,
      transaction.state,
      transaction.appChallenge
    ),
    origin: callbackUrl.origin
  };
};

const oidcCallbackRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse,
  { info, url }: { info: ReturnType<typeof getWsInfo>; url: URL }
) => {
  const guarded = guardOidcRoute(req, res, {
    ip: info?.ip,
    route: '/oidc/callback',
    isNavigation: true
  });

  if (!guarded) return;

  const state = url.searchParams.get('state');
  let toApp = false;

  try {
    const transaction = takeCallbackTransaction(req, state);

    toApp = transaction.appChallenge !== null;

    const { handoffCode, origin } = await completeOidcCallback(
      transaction,
      url,
      info
    );

    let target: URL;

    if (toApp) {
      target = new URL(OIDC_APP_REDIRECT);
      target.searchParams.set('code', handoffCode);
    } else {
      target = new URL(origin);
      target.hash = `oidc=${handoffCode}`;
    }

    res.writeHead(302, {
      'Cache-Control': 'no-store',
      Location: target.toString()
    });
    res.end();
  } catch (error) {
    const code =
      error instanceof OidcCallbackError ? error.code : OidcError.SERVER_ERROR;

    if (error instanceof client.ResponseBodyError) {
      logger.error(
        'OIDC callback failed: provider returned "%s" (%s) with status %d',
        error.error,
        error.error_description ?? 'no description',
        error.status
      );
    } else {
      logger.error('OIDC callback failed: %s', getErrorMessage(error));
    }

    redirectWithError(
      req,
      res,
      code,
      state ? { 'Set-Cookie': clearStateCookie(req, state) } : {},
      toApp
    );
  }
};

export { oidcCallbackRouteHandler };
