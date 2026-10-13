import { SettingsSection } from '@/components/server-screens/settings-shell/section';
import { useStickers } from '@/features/server/stickers/hooks';
import { uploadFiles } from '@/helpers/upload-file';
import { useFilePicker } from '@/hooks/use-file-picker';
import { getTRPCClient } from '@/lib/trpc';
import {
  getTrpcError,
  STICKER_NAME_MAX_LENGTH,
  STICKER_NAME_MIN_LENGTH
} from '@sharkord/shared';
import { Button, Spinner } from '@sharkord/ui';
import { Upload } from 'lucide-react';
import { memo, useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import { StickerRow } from './sticker-row';

// a sticker is named after its file to start with, padded when that is too short
const nameFromFile = (originalName: string) => {
  const base = originalName.replace(/\.[^/.]+$/, '').trim();
  const padded =
    base.length >= STICKER_NAME_MIN_LENGTH ? base : `${base}sticker`;

  return padded.slice(0, STICKER_NAME_MAX_LENGTH);
};

const Stickers = memo(() => {
  const { t } = useTranslation('settings');
  const stickers = useStickers();
  const openFilePicker = useFilePicker();
  const [isUploading, setIsUploading] = useState(false);

  const uploadStickers = useCallback(async () => {
    const files = await openFilePicker(
      'image/png,image/apng,image/gif,image/webp',
      true
    );

    if (!files || files.length === 0) return;

    setIsUploading(true);

    try {
      const trpc = getTRPCClient();
      const temporaryFiles = await uploadFiles(files);

      for (const file of temporaryFiles) {
        await trpc.stickers.add.mutate({
          fileId: file.id,
          name: nameFromFile(file.originalName)
        });
      }

      toast.success(t('stickerCreated'));
    } catch (error) {
      toast.error(getTrpcError(error, t('failedUploadSticker')));
    } finally {
      setIsUploading(false);
    }
  }, [openFilePicker, t]);

  return (
    <SettingsSection
      title={t('stickersTitle')}
      description={t('stickersDesc')}
      action={
        <Button onClick={uploadStickers} disabled={isUploading}>
          {isUploading ? (
            <Spinner size="xxs" />
          ) : (
            <Upload className="h-4 w-4" />
          )}
          {t('uploadStickerBtn')}
        </Button>
      }
    >
      {stickers.length === 0 ? (
        <div className="py-8 text-center text-sm text-muted-foreground">
          {t('noStickersYet')}
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          {stickers.map((sticker) => (
            <StickerRow key={sticker.id} sticker={sticker} />
          ))}
        </div>
      )}
    </SettingsSection>
  );
});

export { Stickers };
