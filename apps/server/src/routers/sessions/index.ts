import { t } from '../../utils/trpc';
import { getSessionsRoute } from './get-sessions';
import { refreshTokenRoute } from './refresh-token';
import { revokeOtherSessionsRoute } from './revoke-other-sessions';
import { revokeSessionRoute } from './revoke-session';

export const sessionsRouter = t.router({
  getAll: getSessionsRoute,
  revoke: revokeSessionRoute,
  revokeOthers: revokeOtherSessionsRoute,
  refreshToken: refreshTokenRoute
});
