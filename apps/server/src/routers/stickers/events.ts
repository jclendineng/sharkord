import { ServerEvents } from '@sharkord/shared';
import { protectedProcedure } from '../../utils/trpc';

const onStickerCreateRoute = protectedProcedure.subscription(
  async ({ ctx }) => {
    return ctx.pubsub.subscribe(ServerEvents.STICKER_CREATE);
  }
);

const onStickerUpdateRoute = protectedProcedure.subscription(
  async ({ ctx }) => {
    return ctx.pubsub.subscribe(ServerEvents.STICKER_UPDATE);
  }
);

const onStickerDeleteRoute = protectedProcedure.subscription(
  async ({ ctx }) => {
    return ctx.pubsub.subscribe(ServerEvents.STICKER_DELETE);
  }
);

export { onStickerCreateRoute, onStickerDeleteRoute, onStickerUpdateRoute };
