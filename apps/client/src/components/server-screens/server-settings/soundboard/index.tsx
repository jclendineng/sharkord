import { SettingsSection } from '@/components/server-screens/settings-shell/section';
import { usePublicServerSettings } from '@/features/server/hooks';
import { useSounds } from '@/features/server/soundboard/hooks';
import { uploadFiles } from '@/helpers/upload-file';
import { useFilePicker } from '@/hooks/use-file-picker';
import { getTRPCClient } from '@/lib/trpc';
import {
  getTrpcError,
  SOUND_NAME_MAX_LENGTH,
  SOUND_NAME_MIN_LENGTH
} from '@sharkord/shared';
import { Button, Spinner } from '@sharkord/ui';
import { Upload } from 'lucide-react';
import { memo, useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import { FreesoundSearch } from './freesound';
import { SoundLibrary } from './library';
import { SoundRow } from './sound-row';

// a sound is named after its file to start with, padded when that is too short
const nameFromFile = (originalName: string) => {
  const base = originalName.replace(/\.[^/.]+$/, '').trim();
  const padded = base.length >= SOUND_NAME_MIN_LENGTH ? base : `${base}sound`;

  return padded.slice(0, SOUND_NAME_MAX_LENGTH);
};

const Soundboard = memo(() => {
  const { t } = useTranslation('settings');
  const sounds = useSounds();
  const settings = usePublicServerSettings();
  const openFilePicker = useFilePicker();
  const [isUploading, setIsUploading] = useState(false);

  const uploadSounds = useCallback(async () => {
    const files = await openFilePicker(
      'audio/mpeg,audio/wav,audio/mp4,.mp3,.wav,.m4a',
      true
    );

    if (!files || files.length === 0) return;

    setIsUploading(true);

    try {
      const trpc = getTRPCClient();
      const temporaryFiles = await uploadFiles(files);

      for (const file of temporaryFiles) {
        await trpc.soundboard.add.mutate({
          fileId: file.id,
          name: nameFromFile(file.originalName)
        });
      }

      toast.success(t('soundCreated'));
    } catch (error) {
      toast.error(getTrpcError(error, t('failedAddSound')));
    } finally {
      setIsUploading(false);
    }
  }, [openFilePicker, t]);

  return (
    <div className="flex flex-col gap-6">
      <SettingsSection
        title={t('soundboardTitle')}
        description={t('soundboardDesc')}
        action={
          <Button onClick={uploadSounds} disabled={isUploading}>
            {isUploading ? (
              <Spinner size="xxs" />
            ) : (
              <Upload className="h-4 w-4" />
            )}
            {t('uploadSoundBtn')}
          </Button>
        }
      >
        {sounds.length === 0 ? (
          <div className="py-8 text-center text-sm text-muted-foreground">
            {t('noSoundsYet')}
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {sounds.map((sound) => (
              <SoundRow key={sound.id} sound={sound} />
            ))}
          </div>
        )}
      </SettingsSection>

      <SettingsSection
        title={t('soundLibraryTitle')}
        description={t('soundLibraryDesc')}
      >
        <SoundLibrary />
      </SettingsSection>

      {settings?.soundSearchEnabled && (
        <SettingsSection
          title={t('freesoundTitle')}
          description={t('freesoundDesc')}
        >
          <FreesoundSearch />
        </SettingsSection>
      )}
    </div>
  );
});

export { Soundboard };
