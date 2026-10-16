import { StreamKind } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { getCurrentVoiceRuntime } from '../../helpers/get-current-voice-runtime';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// stops receiving someone's camera or screen share, for a viewer who turned incoming video off.
// a consumer that is already gone is fine, the result the caller wants is the same
const closeConsumerRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.voiceStream.maxRequests,
  windowMs: config.rateLimiters.voiceStream.windowMs,
  logLabel: 'closeConsumer'
})
  .input(
    z.object({
      remoteId: z.number(),
      kind: z.enum([StreamKind.VIDEO, StreamKind.SCREEN])
    })
  )
  .mutation(async ({ input, ctx }) => {
    const { runtime } = await getCurrentVoiceRuntime(ctx);

    const consumer = runtime.getConsumer(
      ctx.user.id,
      input.remoteId,
      input.kind
    );

    consumer?.close();
  });

export { closeConsumerRoute };
