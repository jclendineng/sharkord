import { and, eq } from 'drizzle-orm';
import { z } from 'zod';
import { db } from '../../db';
import { loginLinks } from '../../db/schema';
import { setLoginLinkStatus } from '../../helpers/login-links';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

// the signed in device lets the one that scanned its qr code in, or turns it away
const approveLoginLinkRoute = protectedProcedure
  .input(z.object({ id: z.string().min(1).max(64), approve: z.boolean() }))
  .mutation(async ({ ctx, input }) => {
    const link = await db
      .select({ status: loginLinks.status, expiresAt: loginLinks.expiresAt })
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

    invariant(link.expiresAt >= Date.now(), {
      code: 'BAD_REQUEST',
      message: 'That sign in code has run out. Show a new one.'
    });

    invariant(link.status === 'claimed', {
      code: 'BAD_REQUEST',
      message: 'No device has scanned that code yet.'
    });

    await setLoginLinkStatus(input.id, input.approve ? 'approved' : 'denied');
  });

export { approveLoginLinkRoute };
