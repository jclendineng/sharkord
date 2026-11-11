import { cn } from '@/lib/utils';
import { IconButton } from '@sharkord/ui';
import { Link, X } from 'lucide-react';
import { memo, useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

const portalRoot = document.getElementById('imagePortal')!;

const MIN_SCALE = 1;
const MAX_SCALE = 5;
const DOUBLE_TAP_SCALE = 2.5;
// how far a pinch may go past either limit under the fingers before it settles back
const PINCH_OVERSHOOT = 0.25;
const DOUBLE_TAP_MS = 300;
const DOUBLE_TAP_DISTANCE = 30;
// a pointer that moved less than this was a tap, not a drag
const TAP_SLOP = 8;
// a drag down this far closes the viewer, and so does a flick, in pixels per millisecond
const DISMISS_DISTANCE = 120;
const DISMISS_VELOCITY = 0.6;
// how far ahead a release carries the picture, in milliseconds of its speed
const MOMENTUM_MS = 200;
const CLOSE_MS = 200;
const SETTLE = 'transform 300ms cubic-bezier(0.2, 0.8, 0.2, 1)';
const STAGE_STYLE: React.CSSProperties = { touchAction: 'none' };
const IMAGE_STYLE: React.CSSProperties = {
  transform: 'scale(0.96)',
  cursor: 'grab'
};

type TPoint = { x: number; y: number };

type TPinch = {
  distance: number;
  middle: TPoint;
  scale: number;
  position: TPoint;
};

type TTap = { time: number; point: TPoint };

type TFullScreenImageProps = React.ImgHTMLAttributes<HTMLImageElement> & {
  as?: React.ElementType;
};

const ORIGIN: TPoint = { x: 0, y: 0 };

const clamp = (value: number, min: number, max: number) =>
  Math.min(Math.max(value, min), max);

const distanceBetween = (a: TPoint, b: TPoint) =>
  Math.hypot(a.x - b.x, a.y - b.y);

// where a point lands once the picture is scaled about an anchor that has to stay put
const scaleAbout = (
  anchor: TPoint,
  position: TPoint,
  ratio: number
): TPoint => ({
  x: anchor.x - (anchor.x - position.x) * ratio,
  y: anchor.y - (anchor.y - position.y) * ratio
});

const FullScreenImage = memo(
  ({ as: Component = 'img', ...props }: TFullScreenImageProps) => {
    const { t } = useTranslation('common');

    const [open, setOpen] = useState(false);
    const [visible, setVisible] = useState(false);

    const stageRef = useRef<HTMLDivElement>(null);
    const imgRef = useRef<HTMLImageElement>(null);
    const closeRef = useRef<HTMLButtonElement>(null);
    const restoreFocusRef = useRef<HTMLElement | null>(null);
    const closeTimerRef = useRef<number | undefined>(undefined);

    const scaleRef = useRef(MIN_SCALE);
    const positionRef = useRef<TPoint>(ORIGIN);
    // every finger or button down on the stage, by pointer id, relative to the stage's center
    const pointersRef = useRef(new Map<number, TPoint>());
    const pinchRef = useRef<TPinch | null>(null);
    const velocityRef = useRef<TPoint>(ORIGIN);
    const lastMoveRef = useRef(0);
    const travelRef = useRef(0);
    const startedOnImageRef = useRef(false);
    const lastTapRef = useRef<TTap | null>(null);

    const applyTransform = useCallback((animated: boolean) => {
      const el = imgRef.current;

      if (!el) return;

      const reducedMotion = window.matchMedia(
        '(prefers-reduced-motion: reduce)'
      );
      const { x, y } = positionRef.current;

      el.style.transition =
        animated && !reducedMotion.matches ? SETTLE : 'none';
      el.style.transform = `translate3d(${x}px, ${y}px, 0) scale(${scaleRef.current})`;
    }, []);

    // a point on the screen relative to the middle of the stage, which is where the picture
    // sits untouched, so an anchor and the picture's offset are in the same terms
    const toStage = useCallback((clientX: number, clientY: number): TPoint => {
      const stage = stageRef.current;

      if (!stage) return ORIGIN;

      const rect = stage.getBoundingClientRect();

      return {
        x: clientX - rect.left - rect.width / 2,
        y: clientY - rect.top - rect.height / 2
      };
    }, []);

    // the furthest the picture may sit from the middle at a scale before an edge of it would
    // come away from the edge of the stage
    const clampPosition = useCallback(
      (position: TPoint, scale: number): TPoint => {
        const el = imgRef.current;
        const stage = stageRef.current;

        if (!el || !stage) return ORIGIN;

        const limitX = Math.max(
          0,
          (el.offsetWidth * scale - stage.clientWidth) / 2
        );
        const limitY = Math.max(
          0,
          (el.offsetHeight * scale - stage.clientHeight) / 2
        );

        return {
          x: clamp(position.x, -limitX, limitX),
          y: clamp(position.y, -limitY, limitY)
        };
      },
      []
    );

    // the stage dims with a drag down, under the finger rather than through its own fade, and
    // goes back to that fade once let go
    const fadeStage = useCallback((opacity: number | null) => {
      const stage = stageRef.current;

      if (!stage) return;

      stage.style.opacity = opacity === null ? '' : String(opacity);
      stage.style.transitionDuration = opacity === null ? '' : '0ms';
    }, []);

    // where the picture is on screen right now, which mid settle is not yet where it is
    // headed. a finger landing then takes it from there, not from the end of the animation
    const catchInFlight = useCallback(() => {
      const el = imgRef.current;

      if (!el) return;

      const computed = getComputedStyle(el);

      if (computed.transform === 'none') return;

      const matrix = new DOMMatrixReadOnly(computed.transform);

      scaleRef.current = matrix.a;
      positionRef.current = { x: matrix.e, y: matrix.f };
    }, []);

    const onOpenClick = useCallback(() => {
      const focused = document.activeElement;

      restoreFocusRef.current = focused instanceof HTMLElement ? focused : null;
      scaleRef.current = MIN_SCALE;
      positionRef.current = ORIGIN;
      pointersRef.current.clear();
      pinchRef.current = null;
      lastTapRef.current = null;

      window.clearTimeout(closeTimerRef.current);
      setOpen(true);
    }, []);

    const onCloseClick = useCallback(() => {
      setVisible(false);
      fadeStage(null);

      window.clearTimeout(closeTimerRef.current);

      // once the fade is over, not on the input path: nothing waits on it to respond
      closeTimerRef.current = window.setTimeout(() => {
        setOpen(false);

        const restoreFocus = restoreFocusRef.current;

        if (restoreFocus) {
          restoreFocus.focus();
        }
      }, CLOSE_MS);
    }, [fadeStage]);

    const onThumbnailKeyDown = useCallback(
      (e: React.KeyboardEvent) => {
        if (e.key !== 'Enter' && e.key !== ' ') return;

        e.preventDefault();
        onOpenClick();
      },
      [onOpenClick]
    );

    const toggleZoom = useCallback(
      (point: TPoint) => {
        if (scaleRef.current > MIN_SCALE) {
          scaleRef.current = MIN_SCALE;
          positionRef.current = ORIGIN;
        } else {
          const ratio = DOUBLE_TAP_SCALE / scaleRef.current;
          const position = scaleAbout(point, positionRef.current, ratio);

          scaleRef.current = DOUBLE_TAP_SCALE;
          positionRef.current = clampPosition(position, DOUBLE_TAP_SCALE);
        }

        applyTransform(true);
      },
      [applyTransform, clampPosition]
    );

    const startPinch = useCallback(() => {
      const [first, second] = [...pointersRef.current.values()];

      pinchRef.current = {
        distance: Math.max(distanceBetween(first, second), 1),
        middle: { x: (first.x + second.x) / 2, y: (first.y + second.y) / 2 },
        scale: scaleRef.current,
        position: positionRef.current
      };
    }, []);

    const handlePointerDown = useCallback(
      (e: React.PointerEvent<HTMLDivElement>) => {
        if (e.pointerType === 'mouse' && e.button !== 0) return;
        if (!(e.target instanceof Element)) return;

        // the bar's buttons keep their own clicks
        const button = e.target.closest('button');

        if (button) return;

        const pointers = pointersRef.current;

        if (pointers.size === 0) {
          const el = imgRef.current;

          travelRef.current = 0;
          velocityRef.current = ORIGIN;
          startedOnImageRef.current = el !== null && el.contains(e.target);
          catchInFlight();
        }

        e.currentTarget.setPointerCapture(e.pointerId);
        pointers.set(e.pointerId, toStage(e.clientX, e.clientY));
        lastMoveRef.current = e.timeStamp;

        if (pointers.size === 2) {
          startPinch();
        }

        applyTransform(false);
      },
      [applyTransform, catchInFlight, startPinch, toStage]
    );

    const handlePointerMove = useCallback(
      (e: React.PointerEvent<HTMLDivElement>) => {
        const pointers = pointersRef.current;
        const previous = pointers.get(e.pointerId);

        if (!previous) return;

        const point = toStage(e.clientX, e.clientY);
        const dx = point.x - previous.x;
        const dy = point.y - previous.y;
        const elapsed = Math.max(e.timeStamp - lastMoveRef.current, 1);

        pointers.set(e.pointerId, point);
        lastMoveRef.current = e.timeStamp;
        travelRef.current += Math.hypot(dx, dy);

        const pinch = pinchRef.current;

        if (pinch && pointers.size >= 2) {
          const [first, second] = [...pointers.values()];
          const middle = {
            x: (first.x + second.x) / 2,
            y: (first.y + second.y) / 2
          };
          const scale = clamp(
            (pinch.scale * distanceBetween(first, second)) / pinch.distance,
            MIN_SCALE - PINCH_OVERSHOOT,
            MAX_SCALE + PINCH_OVERSHOOT
          );
          // the point of the picture that was between the fingers stays between them
          const anchored = scaleAbout(
            pinch.middle,
            pinch.position,
            scale / pinch.scale
          );

          scaleRef.current = scale;
          positionRef.current = {
            x: anchored.x + middle.x - pinch.middle.x,
            y: anchored.y + middle.y - pinch.middle.y
          };
          applyTransform(false);

          return;
        }

        velocityRef.current = {
          x: 0.8 * (dx / elapsed) + 0.2 * velocityRef.current.x,
          y: 0.8 * (dy / elapsed) + 0.2 * velocityRef.current.y
        };

        if (scaleRef.current > MIN_SCALE) {
          positionRef.current = {
            x: positionRef.current.x + dx,
            y: positionRef.current.y + dy
          };
        } else {
          // unzoomed there is nowhere to pan to, a drag down pulls the picture away instead
          const y = Math.max(positionRef.current.y + dy, 0);

          positionRef.current = { x: 0, y };
          fadeStage(1 - Math.min(y / (DISMISS_DISTANCE * 4), 0.6));
        }

        applyTransform(false);
      },
      [applyTransform, fadeStage, toStage]
    );

    const settle = useCallback(() => {
      const velocity = velocityRef.current;

      if (scaleRef.current <= MIN_SCALE) {
        const pulledAway =
          positionRef.current.y > DISMISS_DISTANCE ||
          (positionRef.current.y > TAP_SLOP && velocity.y > DISMISS_VELOCITY);

        scaleRef.current = MIN_SCALE;

        if (pulledAway) {
          onCloseClick();

          return;
        }

        positionRef.current = ORIGIN;
        fadeStage(null);
        applyTransform(true);

        return;
      }

      const scale = Math.min(scaleRef.current, MAX_SCALE);
      // carried on the way it was moving, then held inside the edges
      const thrown = {
        x: positionRef.current.x + velocity.x * MOMENTUM_MS,
        y: positionRef.current.y + velocity.y * MOMENTUM_MS
      };

      scaleRef.current = scale;
      positionRef.current = clampPosition(thrown, scale);
      applyTransform(true);
    }, [applyTransform, clampPosition, fadeStage, onCloseClick]);

    const handleTap = useCallback(
      (e: React.PointerEvent<HTMLDivElement>) => {
        if (!startedOnImageRef.current) {
          onCloseClick();

          return;
        }

        const point = toStage(e.clientX, e.clientY);
        const lastTap = lastTapRef.current;
        const isDoubleTap =
          lastTap !== null &&
          e.timeStamp - lastTap.time < DOUBLE_TAP_MS &&
          distanceBetween(lastTap.point, point) < DOUBLE_TAP_DISTANCE;

        if (isDoubleTap) {
          lastTapRef.current = null;
          toggleZoom(point);

          return;
        }

        lastTapRef.current = { time: e.timeStamp, point };
      },
      [onCloseClick, toStage, toggleZoom]
    );

    const releasePointer = useCallback(
      (e: React.PointerEvent<HTMLDivElement>, cancelled: boolean) => {
        const pointers = pointersRef.current;

        if (!pointers.delete(e.pointerId)) return;

        // one finger left of a pinch carries on as a pan from where it is
        if (pointers.size > 0) {
          if (pointers.size >= 2) {
            startPinch();
          } else {
            pinchRef.current = null;
          }

          velocityRef.current = ORIGIN;

          return;
        }

        const wasPinch = pinchRef.current !== null;
        const wasTap = !cancelled && !wasPinch && travelRef.current < TAP_SLOP;

        pinchRef.current = null;

        if (wasPinch) {
          velocityRef.current = ORIGIN;
        }

        settle();

        if (wasTap) {
          handleTap(e);
        }
      },
      [handleTap, settle, startPinch]
    );

    const handlePointerUp = useCallback(
      (e: React.PointerEvent<HTMLDivElement>) => {
        releasePointer(e, false);
      },
      [releasePointer]
    );

    const handlePointerCancel = useCallback(
      (e: React.PointerEvent<HTMLDivElement>) => {
        releasePointer(e, true);
      },
      [releasePointer]
    );

    useEffect(() => {
      if (!open) return;

      const stage = stageRef.current;

      // the frame after it is in the page, so the fade and the picture growing in both run
      const frame = requestAnimationFrame(() => {
        setVisible(true);
        applyTransform(true);

        const close = closeRef.current;

        if (close) {
          close.focus();
        }
      });

      const handleKeyDown = (e: KeyboardEvent) => {
        if (e.key === 'Escape') {
          e.stopPropagation();
          onCloseClick();

          return;
        }

        if (e.key !== 'Tab' || !stage) return;

        // focus stays on the viewer's own buttons while it covers the page
        const buttons = [...stage.querySelectorAll('button')];
        const index = buttons.findIndex(
          (button) => button === document.activeElement
        );
        const step = e.shiftKey ? -1 : 1;
        const next = buttons[(index + step + buttons.length) % buttons.length];

        e.preventDefault();

        if (next) {
          next.focus();
        }
      };

      // the wheel zooms about the pointer, and a trackpad's pinch arrives as a wheel with ctrl
      const handleWheel = (e: WheelEvent) => {
        e.preventDefault();

        const previous = scaleRef.current;
        const speed = e.ctrlKey ? 0.01 : 0.002;
        const scale = clamp(
          previous * Math.exp(-e.deltaY * speed),
          MIN_SCALE,
          MAX_SCALE
        );
        const anchor = toStage(e.clientX, e.clientY);
        const position = scaleAbout(
          anchor,
          positionRef.current,
          scale / previous
        );

        scaleRef.current = scale;
        positionRef.current = clampPosition(position, scale);
        applyTransform(false);
      };

      document.addEventListener('keydown', handleKeyDown, true);

      if (stage) {
        stage.addEventListener('wheel', handleWheel, { passive: false });
      }

      return () => {
        cancelAnimationFrame(frame);
        document.removeEventListener('keydown', handleKeyDown, true);

        if (stage) {
          stage.removeEventListener('wheel', handleWheel);
        }
      };
    }, [open, onCloseClick, applyTransform, clampPosition, toStage]);

    useEffect(
      () => () => {
        window.clearTimeout(closeTimerRef.current);
      },
      []
    );

    const onCopyLink = useCallback(async () => {
      if (!props.src) return;

      try {
        await navigator.clipboard.writeText(props.src);

        toast.success(t('imageLinkCopied'));
      } catch {
        toast.error(t('failedCopyImageLink'));
      }
    }, [props.src, t]);

    const portalContainer = open
      ? createPortal(
          <div
            ref={stageRef}
            role="dialog"
            aria-modal="true"
            aria-label={props.alt || t('imageViewer')}
            className={cn(
              'fixed inset-0 flex justify-center items-center backdrop-blur-sm bg-black/30 reduce-transparency:bg-black/85 reduce-transparency:backdrop-blur-none z-50 transition-opacity duration-200 select-none',
              visible
                ? 'opacity-100 pointer-events-auto'
                : 'opacity-0 pointer-events-none'
            )}
            style={STAGE_STYLE}
            onPointerDown={handlePointerDown}
            onPointerMove={handlePointerMove}
            onPointerUp={handlePointerUp}
            onPointerCancel={handlePointerCancel}
          >
            <Component
              {...props}
              ref={imgRef}
              style={IMAGE_STYLE}
              className="p-4 max-w-full max-h-full object-contain will-change-transform"
              draggable={false}
            />
            <div className="flex gap-2 absolute top-2 right-2 z-50">
              <IconButton
                icon={Link}
                variant="ghost"
                aria-label={t('copyImageLink')}
                onClick={onCopyLink}
              />
              <IconButton
                ref={closeRef}
                onClick={onCloseClick}
                icon={X}
                variant="ghost"
                aria-label={t('close')}
              />
            </div>
          </div>,
          portalRoot
        )
      : null;

    return (
      <>
        <Component
          {...props}
          className={cn('cursor-pointer', props.className)}
          role="button"
          tabIndex={0}
          onClick={onOpenClick}
          onKeyDown={onThumbnailKeyDown}
          draggable={false}
        />
        {portalContainer}
      </>
    );
  }
);

export { FullScreenImage };
