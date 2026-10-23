import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

type TUseCountdownOptions = {
  seconds: number;
  isActive: boolean;
};

const useCountdown = ({ seconds, isActive }: TUseCountdownOptions) => {
  const [countdown, setCountdown] = useState(seconds);
  const [wasActive, setWasActive] = useState(isActive);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const clearTimer = useCallback(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);

      intervalRef.current = null;
    }
  }, []);

  const reset = useCallback(() => {
    setCountdown(seconds);
  }, [seconds]);

  // turning active starts from the full count, set while rendering as react adjusts state
  // to a changed prop, rather than an effect rendering twice
  if (isActive !== wasActive) {
    setWasActive(isActive);

    if (isActive) {
      setCountdown(seconds);
    }
  }

  useEffect(() => {
    if (!isActive) {
      clearTimer();

      return;
    }

    intervalRef.current = setInterval(() => {
      setCountdown((prev) => {
        if (prev <= 1) {
          clearTimer();

          return 0;
        }

        return prev - 1;
      });
    }, 1000);

    return clearTimer;
  }, [isActive, clearTimer]);

  useEffect(() => clearTimer, [clearTimer]);

  return useMemo(() => ({ countdown, reset }), [countdown, reset]);
};

export { useCountdown };
