import { t } from '../../utils/trpc';
import { addFreesoundSoundRoute } from './add-freesound-sound';
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
import { searchFreesoundRoute } from './search-freesound';
import { updateSoundRoute } from './update-sound';

export const soundboardRouter = t.router({
  add: addSoundRoute,
  addFromLibrary: addLibrarySoundRoute,
  addFromFreesound: addFreesoundSoundRoute,
  searchFreesound: searchFreesoundRoute,
  update: updateSoundRoute,
  delete: deleteSoundRoute,
  getAll: getSoundsRoute,
  getLibrary: getLibraryRoute,
  onCreate: onSoundCreateRoute,
  onUpdate: onSoundUpdateRoute,
  onDelete: onSoundDeleteRoute
});
