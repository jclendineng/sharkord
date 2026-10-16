import { useSounds } from '@/features/server/soundboard/hooks';
import { playSoundFile } from '@/helpers/soundboard-audio';
import { getTRPCClient } from '@/lib/trpc';
import {
  getTrpcError,
  SOUND_MAX_VOLUME,
  type TFreesoundSound
} from '@sharkord/shared';
import { Button, IconButton, Input, Spinner } from '@sharkord/ui';
import { Play, Plus } from 'lucide-react';
import { memo, useCallback, useEffect, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

const SEARCH_DELAY_MS = 400;

type TResultRowProps = {
  sound: TFreesoundSound;
  isAdded: boolean;
};

const ResultRow = memo(({ sound, isAdded }: TResultRowProps) => {
  const { t } = useTranslation('settings');
  const [adding, setAdding] = useState(false);

  const onPreview = useCallback(() => {
    playSoundFile(sound.previewUrl, SOUND_MAX_VOLUME);
  }, [sound.previewUrl]);

  const onAdd = useCallback(async () => {
    setAdding(true);

    try {
      const trpc = getTRPCClient();

      await trpc.soundboard.addFromFreesound.mutate({ freesoundId: sound.id });

      toast.success(t('soundCreated'));
    } catch (error) {
      toast.error(getTrpcError(error, t('failedAddSound')));
    } finally {
      setAdding(false);
    }
  }, [sound.id, t]);

  return (
    <div className="flex items-center gap-2 rounded-md border px-2 py-1.5">
      <IconButton
        icon={Play}
        variant="ghost"
        title={t('previewSoundBtn')}
        onClick={onPreview}
      />
      <div className="flex min-w-0 flex-1 flex-col">
        <span className="truncate text-sm">{sound.name}</span>
        <span className="truncate text-xs text-muted-foreground">
          {t('freesoundCredit', {
            username: sound.username,
            license: sound.license,
            seconds: sound.duration.toFixed(1)
          })}
        </span>
      </div>
      <Button
        size="sm"
        variant="outline"
        onClick={onAdd}
        disabled={adding || isAdded}
      >
        <Plus className="h-4 w-4" />
        {isAdded ? t('soundAddedBtn') : t('addSoundBtn')}
      </Button>
    </div>
  );
});

// sounds found on freesound, only ones free to reuse. a cc by one keeps its credit on the sound
const FreesoundSearch = memo(() => {
  const { t } = useTranslation('settings');
  const sounds = useSounds();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<TFreesoundSound[]>([]);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(false);

  const addedIds = useMemo(
    () => new Set(sounds.map(({ libraryKey }) => libraryKey)),
    [sounds]
  );

  const load = useCallback(
    async (search: string, nextPage: number) => {
      setLoading(true);

      try {
        const trpc = getTRPCClient();
        const result = await trpc.soundboard.searchFreesound.query({
          query: search,
          page: nextPage
        });

        setResults((previous) =>
          nextPage === 1 ? result.sounds : [...previous, ...result.sounds]
        );
        setPage(nextPage);
        setHasMore(result.hasMore);
      } catch (error) {
        toast.error(getTrpcError(error, t('failedSearchSounds')));
      } finally {
        setLoading(false);
      }
    },
    [t]
  );

  useEffect(() => {
    const search = query.trim();

    if (!search) {
      setResults([]);
      setHasMore(false);

      return;
    }

    const timer = setTimeout(() => load(search, 1), SEARCH_DELAY_MS);

    return () => clearTimeout(timer);
  }, [query, load]);

  const onQueryChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) =>
      setQuery(event.target.value),
    []
  );

  const onLoadMore = useCallback(() => {
    load(query.trim(), page + 1);
  }, [load, query, page]);

  return (
    <div className="flex flex-col gap-3">
      <Input
        value={query}
        onChange={onQueryChange}
        placeholder={t('freesoundSearchPlaceholder')}
      />

      {results.length > 0 && (
        <div className="grid gap-2 sm:grid-cols-2">
          {results.map((sound) => (
            <ResultRow
              key={sound.id}
              sound={sound}
              isAdded={addedIds.has(`freesound:${sound.id}`)}
            />
          ))}
        </div>
      )}

      {loading && <Spinner size="xs" />}

      {!loading && hasMore && (
        <Button variant="outline" onClick={onLoadMore}>
          {t('loadMoreSoundsBtn')}
        </Button>
      )}
    </div>
  );
});

export { FreesoundSearch };
