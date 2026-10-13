import { EmojiPickerPanel } from '@/components/emoji-picker/picker-panel';
import type { TEmojiItem } from '@/components/tiptap-input/helpers';
import { usePublicServerSettings } from '@/features/server/hooks';
import type { TGif, TJoinedSticker } from '@sharkord/shared';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger
} from '@sharkord/ui';
import { memo, useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { GifTab } from './gif-tab';
import { StickerTab } from './sticker-tab';

type TExpressionPickerProps = {
  children: React.ReactNode;
  onEmojiSelect: (emoji: TEmojiItem) => void;
  onGifSelect: (gif: TGif) => void;
  onStickerSelect: (sticker: TJoinedSticker) => void;
};

// discord's expression picker for the composer: emoji go into the message, a gif or a
// sticker is sent on its own straight away
const ExpressionPicker = memo(
  ({
    children,
    onEmojiSelect,
    onGifSelect,
    onStickerSelect
  }: TExpressionPickerProps) => {
    const { t } = useTranslation('common');
    const settings = usePublicServerSettings();
    const [open, setOpen] = useState(false);

    const handleEmojiSelect = useCallback(
      (emoji: TEmojiItem) => {
        onEmojiSelect(emoji);
        setOpen(false);
      },
      [onEmojiSelect]
    );

    const handleGifSelect = useCallback(
      (gif: TGif) => {
        onGifSelect(gif);
        setOpen(false);
      },
      [onGifSelect]
    );

    const handleStickerSelect = useCallback(
      (sticker: TJoinedSticker) => {
        onStickerSelect(sticker);
        setOpen(false);
      },
      [onStickerSelect]
    );

    return (
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>{children}</PopoverTrigger>
        <PopoverContent
          className="h-[460px] w-[400px] p-0"
          align="end"
          sideOffset={8}
        >
          <Tabs defaultValue="emoji" className="flex h-full flex-col">
            <TabsList className="grid w-full grid-cols-3 rounded-none border-b">
              <TabsTrigger value="emoji">{t('expressionEmoji')}</TabsTrigger>
              <TabsTrigger value="gifs">{t('expressionGifs')}</TabsTrigger>
              <TabsTrigger value="stickers">
                {t('expressionStickers')}
              </TabsTrigger>
            </TabsList>
            <TabsContent value="emoji" className="mt-0 min-h-0 flex-1">
              <EmojiPickerPanel onEmojiSelect={handleEmojiSelect} />
            </TabsContent>
            <TabsContent value="gifs" className="mt-0 min-h-0 flex-1">
              <GifTab
                enabled={!!settings?.gifsEnabled}
                onSelect={handleGifSelect}
              />
            </TabsContent>
            <TabsContent value="stickers" className="mt-0 min-h-0 flex-1">
              <StickerTab onSelect={handleStickerSelect} />
            </TabsContent>
          </Tabs>
        </PopoverContent>
      </Popover>
    );
  }
);

ExpressionPicker.displayName = 'ExpressionPicker';

export { ExpressionPicker };
