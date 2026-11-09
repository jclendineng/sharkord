import { FileSaveType } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { db } from '../db';
import { removeFile } from '../db/mutations/files';
import { publishUser } from '../db/publishers';
import { getUserById } from '../db/queries/users';
import { users } from '../db/schema';
import { fileManager } from '../helpers/file-manager';
import { invariant } from '../utils/invariant';

type TUserImageTarget = 'avatar' | 'banner';

const saveReplacementImage = async (
  userId: number,
  saveType: FileSaveType,
  fileId?: string
): Promise<number | null> => {
  invariant(!fileId || fileManager.temporaryFileHasMimeType(fileId, 'image/'), {
    code: 'BAD_REQUEST',
    message: 'Invalid file type. Please try again.'
  });

  if (!fileId) return null;

  const tempFile = await fileManager.getTemporaryFile(fileId);

  invariant(tempFile, {
    code: 'NOT_FOUND',
    message: 'Temporary file not found'
  });

  // read from the file itself, a gif renamed to .png is still a gif. a banner may be one
  if (saveType !== FileSaveType.BANNER) {
    const signature = await Bun.file(tempFile.path).slice(0, 4).text();

    invariant(signature !== 'GIF8', {
      code: 'BAD_REQUEST',
      message: "GIFs can't be used as an avatar or server icon."
    });
  }

  const newFile = await fileManager.saveFile(fileId, userId, saveType);

  return newFile.id;
};

const changeUserImage = async (
  userId: number,
  target: TUserImageTarget,
  fileId?: string
) => {
  const isAvatar = target === 'avatar';

  const user = await getUserById(userId);

  invariant(user, {
    code: 'NOT_FOUND',
    message: 'User not found'
  });

  const previousFileId = isAvatar ? user.avatarId : user.bannerId;

  const nextFileId = await saveReplacementImage(
    userId,
    isAvatar ? FileSaveType.AVATAR : FileSaveType.BANNER,
    fileId
  );

  await db
    .update(users)
    .set(isAvatar ? { avatarId: nextFileId } : { bannerId: nextFileId })
    .where(eq(users.id, userId))
    .run();

  if (previousFileId) {
    await removeFile(previousFileId);
  }

  publishUser(userId, 'update');
};

export { changeUserImage, saveReplacementImage };
