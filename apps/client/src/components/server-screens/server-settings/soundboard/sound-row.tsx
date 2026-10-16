import { requestConfirmation } from '@/features/dialogs/actions';
import { getFileUrl } from '@/helpers/get-file-url';
import { playSoundFile } from '@/helpers/soundboard-audio';
import { getTRPCClient } from '@/lib/trpc';
import {
  getTrpcError,
  REACTION_EMOJI_MAX_LENGTH,
  SOUND_MAX_VOLUME,
  SOUND_MIN_VOLUME,
  SOUND_NAME_MAX_LENGTH,
  type TJoinedSoundboardSound
} from '@sharkord/shared';
import { Button, IconButton, Input, Slider } from '@sharkord/ui';
import { Play, Trash2 } from 'lucide-react';
import { memo, useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TSoundRowProps = {
  sound: TJoinedSoundboardSound;
};

const SoundRow = memo(({ sound }: TSoundRowProps) => {
  const { t } = useTranslation('settings');
  const [name, setName] = useState(sound.name);
  const [emoji, setEmoji] = useState(sound.emoji ?? '');
  const [volume, setVolume] = useState(sound.volume);
  const [saving, setSaving] = useState(false);

  const isChanged =
    name.trim() !== sound.name ||
    emoji.trim() !== (sound.emoji ?? '') ||
    volume !== sound.volume;

  const onNameChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => setName(event.target.value),
    []
  );

  const onEmojiChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) =>
      setEmoji(event.target.value),
    []
  );

  const onVolumeChange = useCallback(([value]: number[]) => {
    setVolume(value);
  }, []);

  // at the volume being set, so the change can be heard before saving it
  const onPreview = useCallback(() => {
    playSoundFile(getFileUrl(sound.file), volume);
  }, [sound.file, volume]);

  const onSave = useCallback(async () => {
    setSaving(true);

    try {
      const trpc = getTRPCClient();

      await trpc.soundboard.update.mutate({
        soundId: sound.id,
        name: name.trim(),
        emoji: emoji.trim(),
        volume
      });

      toast.success(t('soundUpdated'));
    } catch (error) {
      toast.error(getTrpcError(error, t('failedUpdateSound')));
    } finally {
      setSaving(false);
    }
  }, [sound.id, name, emoji, volume, t]);

  const onDelete = useCallback(async () => {
    const confirmed = await requestConfirmation({
      title: t('deleteSoundTitle'),
      message: t('deleteSoundMsg', { name: sound.name }),
      confirmLabel: t('deleteSoundBtn')
    });

    if (!confirmed) return;

    try {
      const trpc = getTRPCClient();

      await trpc.soundboard.delete.mutate({ soundId: sound.id });
    } catch (error) {
      toast.error(getTrpcError(error, t('failedDeleteSound')));
    }
  }, [sound.id, sound.name, t]);

  return (
    <div className="flex items-center gap-3 rounded-md border p-3">
      <IconButton
        icon={Play}
        variant="ghost"
        title={t('previewSoundBtn')}
        onClick={onPreview}
      />
      <div className="flex flex-1 flex-col gap-2">
        <div className="flex gap-2">
          <Input
            className="w-16"
            value={emoji}
            onChange={onEmojiChange}
            maxLength={REACTION_EMOJI_MAX_LENGTH}
            placeholder={t('soundEmojiPlaceholder')}
          />
          <Input
            value={name}
            onChange={onNameChange}
            maxLength={SOUND_NAME_MAX_LENGTH}
            placeholder={t('soundNamePlaceholder')}
          />
        </div>
        {sound.attribution && (
          <span className="text-xs text-muted-foreground">
            {sound.attribution}
          </span>
        )}
        <Slider
          min={SOUND_MIN_VOLUME}
          max={SOUND_MAX_VOLUME}
          step={5}
          value={[volume]}
          onValueChange={onVolumeChange}
          rightSlot={
            <span className="w-12 text-right text-sm text-muted-foreground">
              {volume}%
            </span>
          }
        />
      </div>
      <div className="flex flex-col gap-2">
        <Button size="sm" onClick={onSave} disabled={!isChanged || saving}>
          {t('saveSoundBtn')}
        </Button>
        <IconButton
          icon={Trash2}
          variant="ghost"
          title={t('deleteSoundBtn')}
          onClick={onDelete}
        />
      </div>
    </div>
  );
});

export { SoundRow };
