import { logDebug } from '@/helpers/browser-logger';
import { getTRPCClient } from '@/lib/trpc';
import type { TJoinedSticker } from '@sharkord/shared';
import { handleSubscriptionError } from '../subscription-error';
import { removeSticker, upsertSticker } from './actions';

const subscribeToStickers = () => {
  const trpc = getTRPCClient();

  const onCreateSub = trpc.stickers.onCreate.subscribe(undefined, {
    onData: (sticker: TJoinedSticker) => {
      logDebug('[EVENTS] stickers.onCreate', { sticker });
      upsertSticker(sticker);
    },
    onError: handleSubscriptionError('onStickerCreate')
  });

  const onUpdateSub = trpc.stickers.onUpdate.subscribe(undefined, {
    onData: (sticker: TJoinedSticker) => {
      logDebug('[EVENTS] stickers.onUpdate', { sticker });
      upsertSticker(sticker);
    },
    onError: handleSubscriptionError('onStickerUpdate')
  });

  const onDeleteSub = trpc.stickers.onDelete.subscribe(undefined, {
    onData: (stickerId: number) => {
      logDebug('[EVENTS] stickers.onDelete', { stickerId });
      removeSticker(stickerId);
    },
    onError: handleSubscriptionError('onStickerDelete')
  });

  return () => {
    onCreateSub.unsubscribe();
    onUpdateSub.unsubscribe();
    onDeleteSub.unsubscribe();
  };
};

export { subscribeToStickers };
