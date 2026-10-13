import { store } from '@/features/store';
import type { TJoinedSticker } from '@sharkord/shared';
import { serverSliceActions } from '../slice';

export const upsertSticker = (sticker: TJoinedSticker) => {
  store.dispatch(serverSliceActions.upsertSticker(sticker));
};

export const removeSticker = (stickerId: number) => {
  store.dispatch(serverSliceActions.removeSticker({ stickerId }));
};
