import { useSounds } from '@/features/server/soundboard/hooks';
import { getUrlFromServer } from '@/helpers/get-file-url';
import { playSoundFile } from '@/helpers/soundboard-audio';
import { getTRPCClient } from '@/lib/trpc';
import {
  getTrpcError,
  SOUND_MAX_VOLUME,
  SOUNDBOARD_LIBRARY,
  type TSoundboardLibraryKey
} from '@sharkord/shared';
import { Button, IconButton } from '@sharkord/ui';
import { Play, Plus } from 'lucide-react';
import { memo, useCallback, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TLibraryEntry = (typeof SOUNDBOARD_LIBRARY)[number];

type TLibraryRowProps = {
  entry: TLibraryEntry;
};

const LibraryRow = memo(({ entry }: TLibraryRowProps) => {
  const { t } = useTranslation('settings');
  const [adding, setAdding] = useState(false);

  const onPreview = useCallback(() => {
    playSoundFile(
      `${getUrlFromServer()}/soundboard-library/${entry.key}.m4a`,
      SOUND_MAX_VOLUME
    );
  }, [entry.key]);

  const onAdd = useCallback(async () => {
    setAdding(true);

    try {
      const trpc = getTRPCClient();

      await trpc.soundboard.addFromLibrary.mutate({
        key: entry.key as TSoundboardLibraryKey
      });

      toast.success(t('soundCreated'));
    } catch (error) {
      toast.error(getTrpcError(error, t('failedAddSound')));
    } finally {
      setAdding(false);
    }
  }, [entry.key, t]);

  return (
    <div className="flex items-center gap-2 rounded-md border px-2 py-1.5">
      <IconButton
        icon={Play}
        variant="ghost"
        title={t('previewSoundBtn')}
        onClick={onPreview}
      />
      <span className="text-base leading-none">{entry.emoji}</span>
      <span className="flex-1 truncate text-sm">{entry.name}</span>
      <Button size="sm" variant="outline" onClick={onAdd} disabled={adding}>
        <Plus className="h-4 w-4" />
        {t('addSoundBtn')}
      </Button>
    </div>
  );
});

// the sounds the server ships with that this server has not picked yet
const SoundLibrary = memo(() => {
  const sounds = useSounds();

  const unpicked = useMemo(() => {
    const picked = new Set(sounds.map(({ libraryKey }) => libraryKey));

    return SOUNDBOARD_LIBRARY.filter(({ key }) => !picked.has(key));
  }, [sounds]);

  if (unpicked.length === 0) return null;

  return (
    <div className="grid gap-2 sm:grid-cols-2">
      {unpicked.map((entry) => (
        <LibraryRow key={entry.key} entry={entry} />
      ))}
    </div>
  );
});

export { SoundLibrary };
