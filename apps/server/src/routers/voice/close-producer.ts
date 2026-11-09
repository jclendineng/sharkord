import { Permission, ServerEvents, StreamKind } from '@sharkord/shared';
import z from 'zod';
import { getHeldVoiceChannelId } from '../../helpers/voice-seat';
import { logger } from '../../logger';
import { VoiceRuntime } from '../../runtimes/voice';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

const closeProducerRoute = protectedProcedure
  .input(
    z.object({
      kind: z.enum(StreamKind)
    })
  )
  .mutation(async ({ ctx, input }) => {
    await ctx.needsPermission(Permission.JOIN_VOICE_CHANNELS);

    const channelId = getHeldVoiceChannelId(ctx);

    // a socket whose seat another device took over would close that device's stream
    if (!channelId) {
      logger.debug(
        'Ignoring closeProducer for %s/%s: user already left voice',
        ctx.user.name,
        input.kind
      );
      return;
    }

    const runtime = VoiceRuntime.findById(channelId);

    invariant(runtime, {
      code: 'INTERNAL_SERVER_ERROR',
      message: 'Voice runtime not found for this channel'
    });

    const producer = runtime.getProducer(input.kind, ctx.user.id);

    if (!producer) {
      logger.debug(
        'Ignoring closeProducer for %s/%s: producer already missing',
        ctx.user.name,
        input.kind
      );
      return;
    }

    runtime.removeProducer(ctx.user.id, input.kind);

    ctx.pubsub.publishForChannel(
      channelId,
      ServerEvents.VOICE_PRODUCER_CLOSED,
      {
        channelId,
        remoteId: ctx.user.id,
        kind: input.kind
      }
    );
  });

export { closeProducerRoute };
