import { MobileDrawer } from '@/types';
import { useCallback, useRef } from 'react';

// a touch that moved less than this has not picked a direction yet
const SLOP = 10;
// how far ahead a release carries the drawer, in milliseconds of its speed, so a flick
// opens or closes it without the finger covering the distance
const MOMENTUM_MS = 150;
// the share of its width a drawer has to be carried past to go the rest of the way
const COMMIT_SHARE = 0.4;
// what a drawer that cannot be dragged counts as its width, a 50 pixel swipe then opens it
const UNTRACKED_WIDTH = 125;

type TDrawerSwipeOptions = {
  open: MobileDrawer | undefined;
  onOpen: (drawer: MobileDrawer) => void;
  onClose: () => void;
};

type TDrawerSwipeHandlers = {
  onTouchStart: (e: React.TouchEvent) => void;
  onTouchMove: (e: React.TouchEvent) => void;
  onTouchEnd: () => void;
  onTouchCancel: () => void;
};

type TGesture = {
  startX: number;
  startY: number;
  lastX: number;
  lastTime: number;
  dx: number;
  velocity: number;
  drawer: MobileDrawer | undefined;
  isClosing: boolean;
  // the drawer under the finger, missing where it is a column of the page and not a drawer
  element: HTMLElement | null;
  width: number;
};

const clamp = (value: number, min: number, max: number) =>
  Math.min(Math.max(value, min), max);

// only a drawer drawn over the page moves, on a wide screen the same element is a column
const findDrawer = (drawer: MobileDrawer) => {
  const element = document.querySelector<HTMLElement>(
    `[data-drawer="${drawer}"]`
  );

  if (!element || element.offsetWidth === 0) return null;

  const computed = getComputedStyle(element);

  if (computed.position !== 'fixed') return null;

  return element;
};

// the channels come in from the left and the members from the right, so the same travel
// opens one and closes the other
const openingDirection = (drawer: MobileDrawer) =>
  drawer === MobileDrawer.CHANNELS ? 1 : -1;

const offsetFor = (gesture: TGesture, drawer: MobileDrawer) => {
  const direction = openingDirection(drawer);
  const closed = -direction * gesture.width;
  const start = gesture.isClosing ? 0 : closed;

  return clamp(start + gesture.dx, Math.min(closed, 0), Math.max(closed, 0));
};

// the phone's drawers follow the finger: the channels or the members slide with a sideways
// drag from the first pixels of it, and on release go the way they were heading. a swipe
// that only counted once the finger lifted left the drag itself with nothing to show for it
const useDrawerSwipe = ({
  open,
  onOpen,
  onClose
}: TDrawerSwipeOptions): TDrawerSwipeHandlers => {
  const gestureRef = useRef<TGesture | null>(null);

  const handleTouchStart = useCallback((e: React.TouchEvent) => {
    if (e.touches.length !== 1) {
      gestureRef.current = null;

      return;
    }

    const touch = e.touches[0];

    gestureRef.current = {
      startX: touch.clientX,
      startY: touch.clientY,
      lastX: touch.clientX,
      lastTime: e.timeStamp,
      dx: 0,
      velocity: 0,
      drawer: undefined,
      isClosing: false,
      element: null,
      width: UNTRACKED_WIDTH
    };
  }, []);

  const handleTouchMove = useCallback(
    (e: React.TouchEvent) => {
      const gesture = gestureRef.current;

      if (!gesture) return;

      const touch = e.touches[0];
      const dx = touch.clientX - gesture.startX;
      const dy = touch.clientY - gesture.startY;

      if (!gesture.drawer) {
        if (Math.abs(dx) < SLOP && Math.abs(dy) < SLOP) return;

        // mostly up or down is the page scrolling
        if (Math.abs(dx) <= Math.abs(dy)) {
          gestureRef.current = null;

          return;
        }

        const opening = dx > 0 ? MobileDrawer.CHANNELS : MobileDrawer.MEMBERS;
        const drawer = open ?? opening;
        const element = findDrawer(drawer);

        gesture.drawer = drawer;
        gesture.isClosing = open !== undefined;

        if (element) {
          gesture.element = element;
          gesture.width = element.offsetWidth;
          element.style.transition = 'none';
        }
      }

      const elapsed = Math.max(e.timeStamp - gesture.lastTime, 1);

      gesture.velocity =
        0.8 * ((touch.clientX - gesture.lastX) / elapsed) +
        0.2 * gesture.velocity;
      gesture.lastX = touch.clientX;
      gesture.lastTime = e.timeStamp;
      gesture.dx = dx;

      if (gesture.element) {
        const offset = offsetFor(gesture, gesture.drawer);

        // translate, not transform: tailwind places the drawer with the translate property
        // and a transform would be added to that instead of taking its place
        gesture.element.style.translate = `${offset}px 0`;
      }
    },
    [open]
  );

  const release = useCallback(
    (cancelled: boolean) => {
      const gesture = gestureRef.current;

      gestureRef.current = null;

      if (!gesture || !gesture.drawer) return;

      // back to its own classes, whose transition carries it on from where the finger left it
      if (gesture.element) {
        gesture.element.style.transition = '';
        gesture.element.style.translate = '';
      }

      if (cancelled) return;

      const direction = openingDirection(gesture.drawer);
      const thrown = gesture.dx + gesture.velocity * MOMENTUM_MS;
      const travel = direction * thrown;
      const needed = gesture.width * COMMIT_SHARE;

      if (gesture.isClosing && -travel > needed) {
        onClose();
      }

      if (!gesture.isClosing && travel > needed) {
        onOpen(gesture.drawer);
      }
    },
    [onClose, onOpen]
  );

  const handleTouchEnd = useCallback(() => {
    release(false);
  }, [release]);

  const handleTouchCancel = useCallback(() => {
    release(true);
  }, [release]);

  return {
    onTouchStart: handleTouchStart,
    onTouchMove: handleTouchMove,
    onTouchEnd: handleTouchEnd,
    onTouchCancel: handleTouchCancel
  };
};

export { useDrawerSwipe };
