import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { getSettings } from '../../db/queries/server';
import { pushDevices } from '../../db/schema';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const zRelayDevice = z.object({
  // the relay's id for this device on this server, stable across ticket refreshes
  token: z.string().regex(/^[0-9a-f]{64}$/),
  relayTicket: z
    .string()
    .regex(/^[A-Za-z0-9_-]+$/)
    .max(1024),
  // an uncompressed p-256 public key, 65 bytes as unpadded base64url
  encryptionKey: z.string().regex(/^[A-Za-z0-9_-]{87}$/)
});

const isValidEncryptionKey = async (encryptionKey: string) => {
  try {
    await crypto.subtle.importKey(
      'raw',
      Buffer.from(encryptionKey, 'base64url'),
      { name: 'ECDH', namedCurve: 'P-256' },
      false,
      []
    );

    return true;
  } catch {
    return false;
  }
};

const registerDeviceRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.pushDevice.maxRequests,
  windowMs: config.rateLimiters.pushDevice.windowMs,
  logLabel: 'registerPushDevice'
})
  .input(zRelayDevice)
  .mutation(async ({ input, ctx }) => {
    const { pushRelayEnabled } = await getSettings();

    invariant(pushRelayEnabled, {
      code: 'FORBIDDEN',
      message: 'Push notifications are not enabled on this server.'
    });

    invariant(await isValidEncryptionKey(input.encryptionKey), {
      code: 'BAD_REQUEST',
      message: 'This device sent an encryption key that is not valid.'
    });

    const values = {
      userId: ctx.userId,
      tokenVersion: ctx.user.tokenVersion,
      sessionId: ctx.sessionId ?? null,
      relayTicket: input.relayTicket,
      encryptionKey: input.encryptionKey,
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
