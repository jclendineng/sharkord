import { t } from '../../utils/trpc';
import { approveLoginLinkRoute } from './approve-login-link';
import { approveLoginRequestRoute } from './approve-login-request';
import { createLoginLinkRoute } from './create-login-link';
import { getLoginLinkRoute } from './get-login-link';
import { getLoginRequestRoute } from './get-login-request';
import { getSessionsRoute } from './get-sessions';
import { refreshTokenRoute } from './refresh-token';
import { revokeOtherSessionsRoute } from './revoke-other-sessions';
import { revokeSessionRoute } from './revoke-session';

export const sessionsRouter = t.router({
  getAll: getSessionsRoute,
  revoke: revokeSessionRoute,
  revokeOthers: revokeOtherSessionsRoute,
  refreshToken: refreshTokenRoute,
  createLoginLink: createLoginLinkRoute,
  getLoginLink: getLoginLinkRoute,
  approveLoginLink: approveLoginLinkRoute,
  getLoginRequest: getLoginRequestRoute,
  approveLoginRequest: approveLoginRequestRoute
});
