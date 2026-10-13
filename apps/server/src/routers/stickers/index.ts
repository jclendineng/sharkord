import { t } from '../../utils/trpc';
import { addStickerRoute } from './add-sticker';
import { deleteStickerRoute } from './delete-sticker';
import {
  onStickerCreateRoute,
  onStickerDeleteRoute,
  onStickerUpdateRoute
} from './events';
import { getStickersRoute } from './get-stickers';
import { updateStickerRoute } from './update-sticker';

export const stickersRouter = t.router({
  add: addStickerRoute,
  update: updateStickerRoute,
  delete: deleteStickerRoute,
  getAll: getStickersRoute,
  onCreate: onStickerCreateRoute,
  onUpdate: onStickerUpdateRoute,
  onDelete: onStickerDeleteRoute
});
