import { getTRPCClient } from '@/lib/trpc';
import { getTrpcError, type TGif, type TGifCategory } from '@sharkord/shared';
import { Input, Spinner } from '@sharkord/ui';
import { ArrowLeft, TrendingUp } from 'lucide-react';
import { memo, useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';

// what the gif tab is showing: the category tiles it opens with, or a list of gifs
type TMode =
  | { kind: 'categories' }
  | { kind: 'trending' }
  | { kind: 'search'; query: string };

const SEARCH_DELAY_MS = 300;

type TCategoryTileProps = {
  label: string;
  previewUrl?: string;
  icon?: React.ReactNode;
  onClick: () => void;
};

const CategoryTile = memo(
  ({ label, previewUrl, icon, onClick }: TCategoryTileProps) => (
    <button
      type="button"
      onClick={onClick}
      className="relative flex h-24 items-center justify-center overflow-hidden rounded-md bg-muted"
    >
      {previewUrl && (
        <img
          src={previewUrl}
          alt=""
          className="absolute inset-0 h-full w-full object-cover"
          loading="lazy"
        />
      )}
      <span className="absolute inset-0 bg-black/45" />
      <span className="relative flex items-center gap-1.5 font-semibold text-white">
        {icon}
        {label}
      </span>
    </button>
  )
);

type TTermTileProps = {
  category: TGifCategory;
  onSelect: (term: string) => void;
};

const TermTile = memo(({ category, onSelect }: TTermTileProps) => {
  const onClick = useCallback(
    () => onSelect(category.term),
    [category.term, onSelect]
  );

  return (
    <CategoryTile
      label={category.term}
      previewUrl={category.previewUrl}
      onClick={onClick}
    />
  );
});

type TGifTileProps = {
  gif: TGif;
  onSelect: (gif: TGif) => void;
};

const GifTile = memo(({ gif, onSelect }: TGifTileProps) => {
  const onClick = useCallback(() => onSelect(gif), [gif, onSelect]);

  return (
    <button
      type="button"
      onClick={onClick}
      className="mb-1 block w-full overflow-hidden rounded-md"
    >
      <img
        src={gif.previewUrl}
        alt={gif.title}
        className="w-full"
        style={{ aspectRatio: `${gif.width} / ${gif.height}` }}
        loading="lazy"
      />
    </button>
  );
});

type TGifTabProps = {
  enabled: boolean;
  onSelect: (gif: TGif) => void;
};

const GifTab = memo(({ enabled, onSelect }: TGifTabProps) => {
  const { t } = useTranslation('common');
  const [text, setText] = useState('');
  const [mode, setMode] = useState<TMode>({ kind: 'categories' });
  const [categories, setCategories] = useState<TGifCategory[]>([]);
  const [gifs, setGifs] = useState<TGif[]>([]);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string>();

  useEffect(() => {
    if (!enabled) return;

    const load = async () => {
      try {
        const trpc = getTRPCClient();

        setCategories(await trpc.gifs.categories.query());
      } catch (loadError) {
        setError(getTrpcError(loadError, t('gifsLoadFailed')));
      }
    };

    load();
  }, [enabled, t]);

  // a pause in typing searches, clearing the box goes back to the tiles
  useEffect(() => {
    const query = text.trim();
    const timer = setTimeout(() => {
      setMode(query ? { kind: 'search', query } : { kind: 'categories' });
    }, SEARCH_DELAY_MS);

    return () => clearTimeout(timer);
  }, [text]);

  const loadPage = useCallback(
    async (target: TMode, pageNumber: number) => {
      if (target.kind === 'categories') return;

      setLoading(true);
      setError(undefined);

      try {
        const trpc = getTRPCClient();
        const result =
          target.kind === 'search'
            ? await trpc.gifs.search.query({
                query: target.query,
                page: pageNumber
              })
            : await trpc.gifs.trending.query({ page: pageNumber });

        setGifs((current) =>
          pageNumber === 1 ? result.gifs : [...current, ...result.gifs]
        );
        setHasMore(result.hasMore);
        setPage(pageNumber);
      } catch (loadError) {
        setError(getTrpcError(loadError, t('gifsLoadFailed')));
      } finally {
        setLoading(false);
      }
    },
    [t]
  );

  useEffect(() => {
    setGifs([]);
    loadPage(mode, 1);
  }, [mode, loadPage]);

  const onTextChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => setText(event.target.value),
    []
  );

  const onScroll = useCallback(
    (event: React.UIEvent<HTMLDivElement>) => {
      const element = event.currentTarget;
      const nearBottom =
        element.scrollHeight - element.scrollTop - element.clientHeight < 200;

      if (nearBottom && hasMore && !loading) {
        loadPage(mode, page + 1);
      }
    },
    [hasMore, loading, loadPage, mode, page]
  );

  const showTrending = useCallback(() => setMode({ kind: 'trending' }), []);
  const showCategories = useCallback(() => {
    setText('');
    setMode({ kind: 'categories' });
  }, []);

  const onCategory = useCallback((term: string) => setText(term), []);

  if (!enabled) {
    return (
      <div className="flex h-full items-center justify-center p-6 text-center text-sm text-muted-foreground">
        {t('gifsNotSetUp')}
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-2 p-3">
        {mode.kind !== 'categories' && (
          <button type="button" onClick={showCategories} title={t('gifsBack')}>
            <ArrowLeft className="h-4 w-4" />
          </button>
        )}
        <Input
          value={text}
          onChange={onTextChange}
          placeholder={t('searchKlipy')}
          className="h-9"
          autoFocus
        />
      </div>

      <div
        className="min-h-0 flex-1 overflow-y-auto px-3 pb-3"
        onScroll={onScroll}
      >
        {error && (
          <div className="py-4 text-center text-sm text-muted-foreground">
            {error}
          </div>
        )}

        {mode.kind === 'categories' && (
          <div className="grid grid-cols-2 gap-1">
            <CategoryTile
              label={t('trendingGifs')}
              previewUrl={categories[0]?.previewUrl}
              icon={<TrendingUp className="h-4 w-4" />}
              onClick={showTrending}
            />
            {categories.map((category) => (
              <TermTile
                key={category.term}
                category={category}
                onSelect={onCategory}
              />
            ))}
          </div>
        )}

        {mode.kind !== 'categories' && (
          <div className="columns-2 gap-1">
            {gifs.map((gif) => (
              <GifTile key={gif.id} gif={gif} onSelect={onSelect} />
            ))}
          </div>
        )}

        {mode.kind !== 'categories' &&
          !loading &&
          gifs.length === 0 &&
          !error && (
            <div className="py-6 text-center text-sm text-muted-foreground">
              {t('noGifsFound')}
            </div>
          )}

        {loading && (
          <div className="flex justify-center py-3">
            <Spinner size="xs" />
          </div>
        )}
      </div>
    </div>
  );
});

export { GifTab };
