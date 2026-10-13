import { and, eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { pushDevices } from '../../db/schema';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const unregisterDeviceRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.pushDevice.maxRequests,
  windowMs: config.rateLimiters.pushDevice.windowMs,
  logLabel: 'unregisterPushDevice'
})
  .input(
    z.object({
      token: z.string().regex(/^[0-9a-fA-F]{64,200}$/)
    })
  )
  .mutation(async ({ input, ctx }) => {
    // scoped to the caller, so knowing someone else's token is not enough to silence them
    await db
      .delete(pushDevices)
      .where(
        and(
          eq(pushDevices.token, input.token.toLowerCase()),
          eq(pushDevices.userId, ctx.userId)
        )
      );
  });

export { unregisterDeviceRoute };
