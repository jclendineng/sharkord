import { t } from '../../utils/trpc';
import { addLibrarySoundRoute } from './add-library-sound';
import { addSoundRoute } from './add-sound';
import { deleteSoundRoute } from './delete-sound';
import {
  onSoundCreateRoute,
  onSoundDeleteRoute,
  onSoundUpdateRoute
} from './events';
import { getLibraryRoute } from './get-library';
import { getSoundsRoute } from './get-sounds';
import { updateSoundRoute } from './update-sound';

export const soundboardRouter = t.router({
  add: addSoundRoute,
  addFromLibrary: addLibrarySoundRoute,
  update: updateSoundRoute,
  delete: deleteSoundRoute,
  getAll: getSoundsRoute,
  getLibrary: getLibraryRoute,
  onCreate: onSoundCreateRoute,
  onUpdate: onSoundUpdateRoute,
  onDelete: onSoundDeleteRoute
});
