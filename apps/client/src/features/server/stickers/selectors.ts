import type { IRootState } from '@/features/store';

export const stickersSelector = (state: IRootState) => state.server.stickers;
