import { uploadImage } from '@/helpers/upload-file';
import { useFilePicker } from '@/hooks/use-file-picker';
import { getTrpcError } from '@sharkord/shared';
import { useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

export type TPickedImage = {
  fileId: string;
  previewUrl: string;
};

// uploads to the temporary store only, the settings form commits the id when it saves
const usePickImage = ({
  prepare,
  refusesGif
}: {
  prepare?: (file: File) => Promise<File | undefined>;
  refusesGif?: boolean;
} = {}) => {
  const { t } = useTranslation('common');
  const openFilePicker = useFilePicker();

  return useCallback(async (): Promise<TPickedImage | undefined> => {
    try {
      const [picked] = await openFilePicker('image/*');

      if (!picked) return;

      if (refusesGif && picked.type === 'image/gif') {
        toast.error(t('gifNotAllowed'));

        return;
      }

      const file = prepare ? await prepare(picked) : picked;

      if (!file) return;

      const temporaryFile = await uploadImage(file);

      if (!temporaryFile) return;

      return {
        fileId: temporaryFile.id,
        previewUrl: URL.createObjectURL(file)
      };
    } catch (error) {
      toast.error(getTrpcError(error, t('failedUploadImage')));
    }
  }, [openFilePicker, prepare, refusesGif, t]);
};

export { usePickImage };
