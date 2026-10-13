import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { pushDevices } from '../../db/schema';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const registerDeviceRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.pushDevice.maxRequests,
  windowMs: config.rateLimiters.pushDevice.windowMs,
  logLabel: 'registerPushDevice'
})
  .input(
    z.object({
      // an apns device token, hex encoded. 32 bytes today, apple says not to rely on it
      token: z.string().regex(/^[0-9a-fA-F]{64,200}$/),
      sandbox: z.boolean()
    })
  )
  .mutation(async ({ input, ctx }) => {
    invariant(config.push.enabled, {
      code: 'FORBIDDEN',
      message: 'Push notifications are not enabled on this server.'
    });

    const values = {
      userId: ctx.userId,
      tokenVersion: ctx.user.tokenVersion,
      sessionId: ctx.sessionId ?? null,
      sandbox: input.sandbox,
      createdAt: Date.now()
    };

    // a token identifies a device, so one that signs in to another account moves with it
    // rather than notifying both accounts
    await db
      .insert(pushDevices)
      .values({ ...values, token: input.token.toLowerCase() })
      .onConflictDoUpdate({ target: pushDevices.token, set: values });
  });

export { registerDeviceRoute };
