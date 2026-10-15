import { and, eq } from 'drizzle-orm';
import { z } from 'zod';
import { db } from '../../db';
import { loginLinks } from '../../db/schema';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

// asked every couple of seconds while the qr code is up: whether a device has scanned it, and
// which, so it can be approved
const getLoginLinkRoute = protectedProcedure
  .input(z.object({ id: z.string().min(1).max(64) }))
  .query(async ({ ctx, input }) => {
    const link = await db
      .select({
        status: loginLinks.status,
        os: loginLinks.claimedOs,
        device: loginLinks.claimedDevice,
        expiresAt: loginLinks.expiresAt
      })
      .from(loginLinks)
      .where(
        and(eq(loginLinks.id, input.id), eq(loginLinks.userId, ctx.userId))
      )
      .limit(1)
      .get();

    invariant(link, {
      code: 'NOT_FOUND',
      message: 'That sign in code is gone. Show a new one.'
    });

    return {
      ...link,
      status: link.expiresAt < Date.now() ? 'expired' : link.status
    };
  });

export { getLoginLinkRoute };
