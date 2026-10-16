import { ServerEvents } from '@sharkord/shared';
import { protectedProcedure } from '../../utils/trpc';

const onSoundCreateRoute = protectedProcedure.subscription(async ({ ctx }) => {
  return ctx.pubsub.subscribe(ServerEvents.SOUND_CREATE);
});

const onSoundUpdateRoute = protectedProcedure.subscription(async ({ ctx }) => {
  return ctx.pubsub.subscribe(ServerEvents.SOUND_UPDATE);
});

const onSoundDeleteRoute = protectedProcedure.subscription(async ({ ctx }) => {
  return ctx.pubsub.subscribe(ServerEvents.SOUND_DELETE);
});

export { onSoundCreateRoute, onSoundDeleteRoute, onSoundUpdateRoute };
