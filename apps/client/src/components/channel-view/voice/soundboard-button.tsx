import { Emoji } from '@/components/emoji';
import { useSounds } from '@/features/server/soundboard/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { getTrpcError, type TJoinedSoundboardSound } from '@sharkord/shared';
import {
  Button,
  Popover,
  PopoverContent,
  PopoverTrigger,
  Tooltip
} from '@sharkord/ui';
import { AudioLines } from 'lucide-react';
import { memo, useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TSoundTileProps = {
  sound: TJoinedSoundboardSound;
  onPlay: (soundId: number) => void;
};

const SoundTile = memo(({ sound, onPlay }: TSoundTileProps) => {
  const handleClick = useCallback(() => onPlay(sound.id), [onPlay, sound.id]);

  return (
    <button
      type="button"
      onClick={handleClick}
      className="flex min-w-0 items-center gap-1.5 rounded-md bg-muted/60 px-2 py-1.5 text-left text-sm transition-colors hover:bg-accent cursor-pointer"
    >
      {sound.emoji && (
        <Emoji
          emoji={sound.emoji}
          file={null}
          className="size-4 shrink-0"
          nativeEmojiClassName="text-base leading-none"
        />
      )}
      <span className="truncate">{sound.name}</span>
    </button>
  );
});

SoundTile.displayName = 'SoundTile';

// discord's soundboard in the call's controls: a grid of the server's sounds, each played for
// everyone in the call on a click
const SoundboardButton = memo(() => {
  const { t } = useTranslation('common');
  const sounds = useSounds();
  const [open, setOpen] = useState(false);

  const playSound = useCallback(
    async (soundId: number) => {
      try {
        const trpc = getTRPCClient();

        await trpc.voice.playSound.mutate({ soundId });
      } catch (error) {
        toast.error(getTrpcError(error, t('failedPlaySound')));
      }
    },
    [t]
  );

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <Tooltip content={t('soundboard')}>
        <PopoverTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className="rounded size-8 transition-all duration-200 hover:bg-muted/60"
            aria-label={t('soundboard')}
          >
            <AudioLines className="size-4" />
          </Button>
        </PopoverTrigger>
      </Tooltip>
      <PopoverContent className="w-80 p-2" align="center" sideOffset={12}>
        {sounds.length === 0 ? (
          <div className="py-6 text-center text-sm text-muted-foreground">
            {t('noSoundsYet')}
          </div>
        ) : (
          <div className="grid max-h-72 grid-cols-2 gap-1.5 overflow-y-auto">
            {sounds.map((sound) => (
              <SoundTile key={sound.id} sound={sound} onPlay={playSound} />
            ))}
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
});

SoundboardButton.displayName = 'SoundboardButton';

export { SoundboardButton };
