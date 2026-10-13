import { getActiveSessions } from '../../db/queries/sessions';
import { SESSION_TOKEN_TTL_MS } from '../../helpers/sessions';
import { protectedProcedure } from '../../utils/trpc';

// the caller's own signed in devices, the one asking marked as current
const getSessionsRoute = protectedProcedure.query(async ({ ctx }) => {
  const sessions = await getActiveSessions(
    ctx.userId,
    Date.now() - SESSION_TOKEN_TTL_MS
  );

  return sessions.map((session) => ({
    ...session,
    isCurrent: session.id === ctx.sessionId
  }));
});

export { getSessionsRoute };
