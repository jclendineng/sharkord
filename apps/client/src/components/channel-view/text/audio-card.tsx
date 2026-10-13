import { Button } from '@sharkord/ui';
import { filesize } from 'filesize';
import { FileMusic, Trash } from 'lucide-react';
import { memo, useCallback } from 'react';

type TAudioCardProps = {
  name: string;
  size: number;
  src: string;
  onRemove?: () => void;
};

// an audio attachment, a voice message from the ios app among them, plays where it is
const AudioCard = memo(({ name, size, src, onRemove }: TAudioCardProps) => {
  const onRemoveClick = useCallback(
    (e: React.MouseEvent) => {
      if (onRemove) {
        e.preventDefault();
        onRemove();
      }
    },
    [onRemove]
  );

  return (
    <div className="flex w-full max-w-sm flex-col gap-2 rounded-lg border border-border bg-background p-2">
      <div className="flex items-center gap-3">
        <div className="flex shrink-0 items-center justify-center rounded-md bg-muted p-2">
          <FileMusic className="h-5 w-5 text-muted-foreground" />
        </div>
        <div className="flex flex-1 flex-col overflow-hidden">
          <span className="truncate text-sm font-medium text-foreground">
            {name}
          </span>
          <span className="text-xs text-muted-foreground">
            {filesize(size)}
          </span>
        </div>
        {onRemove && (
          <Button
            size="icon"
            variant="ghost"
            className="h-8 w-8 shrink-0"
            onClick={onRemoveClick}
          >
            <Trash className="h-4 w-4" />
          </Button>
        )}
      </div>
      <audio src={src} controls preload="metadata" className="w-full" />
    </div>
  );
});

export { AudioCard };
