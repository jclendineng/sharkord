import { t } from '../../utils/trpc';
import { deleteFileRoute } from './delete-file';
import { deleteTemporaryFileRoute } from './delete-temporary-file';
import { signFilesRoute } from './sign-files';

export const filesRouter = t.router({
  delete: deleteFileRoute,
  deleteTemporary: deleteTemporaryFileRoute,
  sign: signFilesRoute
});
