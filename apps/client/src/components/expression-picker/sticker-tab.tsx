import { useStickers } from '@/features/server/stickers/hooks';
import { getFileUrl } from '@/helpers/get-file-url';
import type { TJoinedSticker } from '@sharkord/shared';
import { Input, Tooltip } from '@sharkord/ui';
import { memo, useCallback, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';

type TStickerTileProps = {
  sticker: TJoinedSticker;
  onSelect: (sticker: TJoinedSticker) => void;
};

const StickerTile = memo(({ sticker, onSelect }: TStickerTileProps) => {
  const onClick = useCallback(() => onSelect(sticker), [sticker, onSelect]);

  return (
    <Tooltip content={sticker.name}>
      <button
        type="button"
        onClick={onClick}
        className="rounded-md p-1 hover:bg-accent"
      >
        <img
          src={getFileUrl(sticker.file)}
          alt={sticker.name}
          className="aspect-square w-full object-contain"
          loading="lazy"
        />
      </button>
    </Tooltip>
  );
});

type TStickerTabProps = {
  onSelect: (sticker: TJoinedSticker) => void;
};

const StickerTab = memo(({ onSelect }: TStickerTabProps) => {
  const { t } = useTranslation('common');
  const stickers = useStickers();
  const [search, setSearch] = useState('');

  const shown = useMemo(() => {
    const query = search.trim().toLowerCase();

    return query
      ? stickers.filter(
          (sticker) =>
            sticker.name.toLowerCase().includes(query) ||
            (sticker.description ?? '').toLowerCase().includes(query)
        )
      : stickers;
  }, [stickers, search]);

  const onSearchChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) =>
      setSearch(event.target.value),
    []
  );

  return (
    <div className="flex h-full flex-col">
      <div className="p-3">
        <Input
          value={search}
          onChange={onSearchChange}
          placeholder={t('searchStickers')}
          className="h-9"
          autoFocus
        />
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto px-3 pb-3">
        {shown.length === 0 ? (
          <div className="py-6 text-center text-sm text-muted-foreground">
            {stickers.length === 0 ? t('noStickers') : t('noStickersFound')}
          </div>
        ) : (
          <div className="grid grid-cols-4 gap-1">
            {shown.map((sticker) => (
              <StickerTile
                key={sticker.id}
                sticker={sticker}
                onSelect={onSelect}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
});

export { StickerTab };
