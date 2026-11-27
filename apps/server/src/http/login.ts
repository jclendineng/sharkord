import {
  ActivityLogType,
  DELETED_USER_IDENTITY_AND_NAME,
  IP_BANNED_MESSAGE,
  TOTP_REQUIRED_MESSAGE,
  sha256,
  type TBeforeLoginPayload
} from '@sharkord/shared';
import chalk from 'chalk';
import { eq } from 'drizzle-orm';
import http from 'http';

import z from 'zod';
import { config } from '../config';
import { db } from '../db';
import { createUser } from '../db/mutations/users';
import { publishUser } from '../db/publishers';
import { isInviteValid } from '../db/queries/invites';
import { isIpBanned } from '../db/queries/ip-bans';
import { getSettings } from '../db/queries/server';
import { getUserByIdentity } from '../db/queries/users';
import { users } from '../db/schema';
import { getWsInfo } from '../helpers/get-ws-info';
import { getIpBlockKey } from '../helpers/network';
import { isLocalLoginDisabled } from '../helpers/oidc/settings';
import { safeCompare } from '../helpers/safe-compare';
import { createSessionToken } from '../helpers/sessions';
import { checkSecondFactor } from '../helpers/two-factor';
import { logger } from '../logger';
import { pluginManager } from '../plugins';
import { runHook } from '../plugins/run-hook';
import { enqueueActivityLog } from '../queues/activity-log';
import {
  createFailedAttemptsLimiter,
  createRateLimiter,
  getRateLimitRetrySeconds
} from '../utils/rate-limiters/rate-limiter';
import { HttpValidationError } from './errors';
import { enforceHttpRateLimit, getJsonBody, sendJsonError } from './helpers';

const zBody = z.object({
  identity: z
    .string()
    .trim()
    .toLowerCase()
    .min(1, 'Identity must be at least 1 character long'),
  password: z
    .string()
    .min(4, 'Password must be at least 4 characters long')
    .max(128),
  invite: z.string().optional(),
  // the authenticator or recovery code, asked for once the password is right
  totp: z.string().trim().max(12).optional()
});

const loginRateLimiter = createRateLimiter({
  maxRequests: config.rateLimiters.login.maxRequests,
  windowMs: config.rateLimiters.login.windowMs
});

const loginIdentityRateLimiter = createRateLimiter({
  maxRequests: config.rateLimiters.loginIdentity.maxRequests,
  windowMs: config.rateLimiters.loginIdentity.windowMs
});

// only the password route counts failures, so qr sign in, login links and sso are never locked
const loginLockout = createFailedAttemptsLimiter(
  config.rateLimiters.loginLockout
);

const GENERIC_LOGIN_ERROR = 'Invalid credentials';

// a wrong password and a wrong two factor code both count, or someone holding the password
// could guess codes from one address without end
const recordLoginFailure = (lockoutKey: string | undefined) => {
  if (!lockoutKey) return;

  const blockMs = loginLockout.recordFailure(lockoutKey);

  if (blockMs > 0) {
    logger.warn(
      `${chalk.dim('[Auth]')} Blocked login attempts from ${lockoutKey} for ${Math.ceil(blockMs / 60_000)} minutes after repeated failures.`
    );
  }
};

const invalidCredentialsError = (lockoutKey: string | undefined) => {
  recordLoginFailure(lockoutKey);

  return new HttpValidationError('identity', GENERIC_LOGIN_ERROR);
};

let dummyArgon2HashPromise: Promise<string> | null = null;
const getDummyArgon2Hash = (): Promise<string> => {
  if (!dummyArgon2HashPromise) {
    dummyArgon2HashPromise = Bun.password
      .hash('sharkord-dummy-password-for-timing')
      .catch((error) => {
        dummyArgon2HashPromise = null;
        throw error;
      });
  }
  return dummyArgon2HashPromise;
};

const loginRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse
) => {
  const connectionInfo = getWsInfo(undefined, req);
  const lockoutKey = connectionInfo?.ip
    ? getIpBlockKey(connectionInfo.ip)
    : undefined;

  // a rate limit step, before the body is read, so a locked address learns nothing
  if (lockoutKey) {
    const retryAfterMs = loginLockout.getRetryAfterMs(lockoutKey);

    if (retryAfterMs > 0) {
      res.setHeader('Retry-After', getRateLimitRetrySeconds(retryAfterMs));
      sendJsonError(
        res,
        429,
        'Too many failed login attempts. Please try again later.'
      );

      return;
    }
  }

  const data = zBody.parse(await getJsonBody(req));

  if (data.identity === DELETED_USER_IDENTITY_AND_NAME) {
    throw new HttpValidationError('identity', 'This identity is reserved');
  }

  if (isLocalLoginDisabled()) {
    throw new HttpValidationError(
      'identity',
      'This server only accepts sign in through its identity provider'
    );
  }

  const settings = await getSettings();
  let existingUser = await getUserByIdentity(data.identity);

  await runHook<TBeforeLoginPayload, never>({
    entries: pluginManager.getHooks('beforeLogin'),
    payload: {
      identity: data.identity,
      ip: connectionInfo?.ip,
      isExistingUser: !!existingUser
    },
    reject: (message) => {
      throw new HttpValidationError('identity', message);
    }
  });

  const allowed = enforceHttpRateLimit(
    res,
    loginRateLimiter,
    connectionInfo?.ip,
    {
      route: '/login',
      message: 'Too many login attempts. Please try again shortly.'
    }
  );

  if (!allowed) return;

  const identityAllowed = enforceHttpRateLimit(
    res,
    loginIdentityRateLimiter,
    `identity:${data.identity}`,
    {
      route: '/login',
      message: 'Too many login attempts. Please try again shortly.'
    }
  );

  if (!identityAllowed) return;

  // before an account is found or made, so a banned network cannot sign up a new one either
  if (await isIpBanned(connectionInfo?.ip)) {
    throw new HttpValidationError('identity', IP_BANNED_MESSAGE);
  }

  if (!existingUser) {
    const result = await isInviteValid(data.invite);

    if (!settings.allowNewUsers && result.error) {
      await Bun.password.verify('dummy', await getDummyArgon2Hash());

      logger.info(
        `${chalk.dim('[Auth]')} Login attempt for unknown identity blocked. (reason: ${result.error}, IP: ${connectionInfo?.ip || 'unknown'})`
      );

      throw invalidCredentialsError(lockoutKey);
    }

    // only consume the invite when one was actually accepted
    const usedInviteCode = result.invite ? data.invite : undefined;

    const inviteRoleId = result.invite?.roleId ?? null;

    // user doesn't exist, but registration is open OR invite was valid - create the user automatically
    const registeredUserId = await createUser({
      identity: data.identity,
      hashedPassword: (await Bun.password.hash(data.password)).toString(),
      inviteCode: usedInviteCode,
      inviteRoleId
    });

    existingUser = await getUserByIdentity(data.identity);

    if (!existingUser) {
      throw new Error('User registration failed');
    }

    // published only once the registration transaction has committed
    publishUser(registeredUserId, 'create');

    if (usedInviteCode) {
      enqueueActivityLog({
        type: ActivityLogType.USED_INVITE,
        userId: registeredUserId,
        details: { code: usedInviteCode },
        ip: connectionInfo?.ip
      });
    }
  }

  // temporary logic to migrate old SHA256 password hashes to argon2 on login
  const isPasswordArgon = existingUser.password.startsWith('$argon2');

  let passwordMatches: boolean;

  if (isPasswordArgon) {
    passwordMatches = await Bun.password.verify(
      data.password,
      existingUser.password
    );
  } else {
    logger.info(
      `${chalk.dim('[Auth]')} User "${existingUser.identity}" is using legacy SHA256 password hash, upgrading to argon2...`
    );

    const hashInputPassword = await sha256(data.password);

    passwordMatches = safeCompare(hashInputPassword, existingUser.password);

    if (passwordMatches) {
      const argon2Password = await Bun.password.hash(data.password);

      await db
        .update(users)
        .set({
          password: argon2Password
        })
        .where(eq(users.id, existingUser.id));
    }
  }

  if (!passwordMatches) {
    logger.info(
      `${chalk.dim('[Auth]')} Failed login attempt for user "${existingUser.identity}" due to invalid password. (IP: ${connectionInfo?.ip || 'unknown'})`
    );

    throw invalidCredentialsError(lockoutKey);
  }

  if (existingUser.banned) {
    throw new HttpValidationError(
      'identity',
      `Identity banned: ${existingUser.banReason || 'No reason provided'}`
    );
  }

  const secondFactor = await checkSecondFactor(existingUser.id, data.totp);

  // only reached with the right password, so asking for the code says nothing to a guesser
  if (secondFactor === 'missing') {
    throw new HttpValidationError('totp', TOTP_REQUIRED_MESSAGE);
  }

  if (secondFactor === 'invalid') {
    logger.info(
      `${chalk.dim('[Auth]')} Failed two-factor code for user "${existingUser.identity}". (IP: ${connectionInfo?.ip || 'unknown'})`
    );

    recordLoginFailure(lockoutKey);

    throw new HttpValidationError('totp', "That code isn't right.");
  }

  const token = await createSessionToken(
    existingUser.id,
    existingUser.tokenVersion,
    connectionInfo
  );

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ success: true, token }));

  return res;
};

export { loginRouteHandler };
