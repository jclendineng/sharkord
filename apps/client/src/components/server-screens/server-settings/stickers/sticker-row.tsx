import { requestConfirmation } from '@/features/dialogs/actions';
import { getFileUrl } from '@/helpers/get-file-url';
import { getTRPCClient } from '@/lib/trpc';
import {
  getTrpcError,
  STICKER_DESCRIPTION_MAX_LENGTH,
  STICKER_NAME_MAX_LENGTH,
  type TJoinedSticker
} from '@sharkord/shared';
import { Button, IconButton, Input } from '@sharkord/ui';
import { Trash2 } from 'lucide-react';
import { memo, useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TStickerRowProps = {
  sticker: TJoinedSticker;
};

const StickerRow = memo(({ sticker }: TStickerRowProps) => {
  const { t } = useTranslation('settings');
  const [name, setName] = useState(sticker.name);
  const [description, setDescription] = useState(sticker.description ?? '');
  const [saving, setSaving] = useState(false);

  const isChanged =
    name.trim() !== sticker.name ||
    description.trim() !== (sticker.description ?? '');

  const onNameChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => setName(event.target.value),
    []
  );

  const onDescriptionChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) =>
      setDescription(event.target.value),
    []
  );

  const onSave = useCallback(async () => {
    setSaving(true);

    try {
      const trpc = getTRPCClient();

      await trpc.stickers.update.mutate({
        stickerId: sticker.id,
        name: name.trim(),
        description: description.trim()
      });

      toast.success(t('stickerUpdated'));
    } catch (error) {
      toast.error(getTrpcError(error, t('failedUpdateSticker')));
    } finally {
      setSaving(false);
    }
  }, [sticker.id, name, description, t]);

  const onDelete = useCallback(async () => {
    const confirmed = await requestConfirmation({
      title: t('deleteStickerTitle'),
      message: t('deleteStickerMsg', { name: sticker.name }),
      confirmLabel: t('deleteStickerBtn')
    });

    if (!confirmed) return;

    try {
      const trpc = getTRPCClient();

      await trpc.stickers.delete.mutate({ stickerId: sticker.id });
    } catch (error) {
      toast.error(getTrpcError(error, t('failedDeleteSticker')));
    }
  }, [sticker.id, sticker.name, t]);

  return (
    <div className="flex items-center gap-3 rounded-md border p-3">
      <img
        src={getFileUrl(sticker.file)}
        alt={sticker.name}
        className="h-16 w-16 shrink-0 object-contain"
        loading="lazy"
      />
      <div className="flex flex-1 flex-col gap-2">
        <Input
          value={name}
          onChange={onNameChange}
          maxLength={STICKER_NAME_MAX_LENGTH}
          placeholder={t('stickerNamePlaceholder')}
        />
        <Input
          value={description}
          onChange={onDescriptionChange}
          maxLength={STICKER_DESCRIPTION_MAX_LENGTH}
          placeholder={t('stickerDescriptionPlaceholder')}
        />
      </div>
      <div className="flex flex-col gap-2">
        <Button size="sm" onClick={onSave} disabled={!isChanged || saving}>
          {t('saveStickerBtn')}
        </Button>
        <IconButton
          icon={Trash2}
          variant="ghost"
          title={t('deleteStickerBtn')}
          onClick={onDelete}
        />
      </div>
    </div>
  );
});

export { StickerRow };
