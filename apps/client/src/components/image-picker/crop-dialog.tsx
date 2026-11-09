import {
  Button,
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  Slider
} from '@sharkord/ui';
import {
  memo,
  useCallback,
  useEffect,
  useRef,
  useState,
  type PointerEvent,
  type SyntheticEvent
} from 'react';
import { useTranslation } from 'react-i18next';
import {
  clampCropOffset,
  CROP_SIDE,
  getCropDisplaySize,
  getCropDrawRect
} from './helpers';

const OUTPUT_SIDE = 512;
const MAX_ZOOM = 5;
const ZOOM_STEP = 0.01;

type TCropDialogProps = {
  file: File;
  onDone: (file: File | undefined) => void;
};

const CropDialog = memo(({ file, onDone }: TCropDialogProps) => {
  const { t } = useTranslation('common');
  const [objectUrl, setObjectUrl] = useState<string>();
  const imageRef = useRef<HTMLImageElement>(null);
  const dragStart = useRef<{ pointerX: number; pointerY: number } | null>(null);
  const [imageSize, setImageSize] = useState({ width: 1, height: 1 });
  const [zoom, setZoom] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });

  // made here with its release, an effect that runs twice must not be left holding a revoked url
  useEffect(() => {
    const url = URL.createObjectURL(file);

    setObjectUrl(url);

    return () => URL.revokeObjectURL(url);
  }, [file]);

  const handleImageLoad = useCallback(
    (event: SyntheticEvent<HTMLImageElement>) => {
      const { naturalWidth, naturalHeight } = event.currentTarget;

      setImageSize({ width: naturalWidth, height: naturalHeight });
    },
    []
  );

  const handlePointerDown = useCallback(
    (event: PointerEvent<HTMLDivElement>) => {
      event.currentTarget.setPointerCapture(event.pointerId);

      dragStart.current = {
        pointerX: event.clientX - offset.x,
        pointerY: event.clientY - offset.y
      };
    },
    [offset]
  );

  const handlePointerMove = useCallback(
    (event: PointerEvent<HTMLDivElement>) => {
      if (!dragStart.current) return;

      const { pointerX, pointerY } = dragStart.current;

      setOffset(
        clampCropOffset(
          { x: event.clientX - pointerX, y: event.clientY - pointerY },
          imageSize,
          zoom
        )
      );
    },
    [imageSize, zoom]
  );

  const handlePointerUp = useCallback(() => {
    dragStart.current = null;
  }, []);

  const handleZoomChange = useCallback(
    ([nextZoom = 1]: number[]) => {
      setZoom(nextZoom);
      setOffset((current) => clampCropOffset(current, imageSize, nextZoom));
    },
    [imageSize]
  );

  const handleOpenChange = useCallback(
    (isOpen: boolean) => {
      if (!isOpen) onDone(undefined);
    },
    [onDone]
  );

  const handleCancel = useCallback(() => onDone(undefined), [onDone]);

  const handleUse = useCallback(() => {
    const image = imageRef.current;
    const canvas = document.createElement('canvas');

    canvas.width = OUTPUT_SIDE;
    canvas.height = OUTPUT_SIDE;

    const context = canvas.getContext('2d');

    // a file the browser could not decode has nothing to draw
    if (!image?.naturalWidth || !context) {
      onDone(undefined);

      return;
    }

    const { x, y, width, height } = getCropDrawRect(
      imageSize,
      zoom,
      offset,
      OUTPUT_SIDE
    );

    context.drawImage(image, x, y, width, height);

    canvas.toBlob((blob) => {
      onDone(
        blob ? new File([blob], 'logo.png', { type: 'image/png' }) : undefined
      );
    }, 'image/png');
  }, [imageSize, zoom, offset, onDone]);

  const { width, height } = getCropDisplaySize(imageSize, zoom);

  return (
    <Dialog open onOpenChange={handleOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t('cropImageTitle')}</DialogTitle>
        </DialogHeader>
        <div
          className="relative flex h-[348px] touch-none cursor-move items-center justify-center overflow-hidden rounded-md bg-black"
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          onPointerCancel={handlePointerUp}
        >
          <img
            ref={imageRef}
            src={objectUrl}
            alt=""
            draggable={false}
            onLoad={handleImageLoad}
            className="absolute max-w-none select-none"
            style={{
              width,
              height,
              transform: `translate(${offset.x}px, ${offset.y}px)`
            }}
          />
          <div
            className="pointer-events-none relative rounded-[22%] border-2 border-white shadow-[0_0_0_9999px_rgba(0,0,0,0.55)]"
            style={{ width: CROP_SIDE, height: CROP_SIDE }}
          />
        </div>
        <Slider
          aria-label={t('cropImageZoom')}
          min={1}
          max={MAX_ZOOM}
          step={ZOOM_STEP}
          value={[zoom]}
          onValueChange={handleZoomChange}
        />
        <DialogFooter>
          <Button variant="outline" onClick={handleCancel}>
            {t('cancel')}
          </Button>
          <Button onClick={handleUse}>{t('cropImageUse')}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
});

export { CropDialog };
