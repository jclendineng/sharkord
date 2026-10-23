import { useEffect, useState } from 'react';

const getSecondsLeft = (target: number | null) => {
  if (target === null) return 0;

  return Math.max(0, Math.ceil((target - Date.now()) / 1000));
};

const useCountdownSeconds = (target: number | null) => {
  const [secondsLeft, setSecondsLeft] = useState(() => getSecondsLeft(target));
  const [countedTarget, setCountedTarget] = useState(target);

  // a new target starts counting from its own time straight away, set while rendering as
  // react adjusts state to a changed prop, rather than an effect rendering twice
  if (target !== countedTarget) {
    setCountedTarget(target);
    setSecondsLeft(getSecondsLeft(target));
  }

  useEffect(() => {
    if (target === null) return;

    const timer = setInterval(
      () => setSecondsLeft(getSecondsLeft(target)),
      250
    );

    return () => clearInterval(timer);
  }, [target]);

  return secondsLeft;
};

export { useCountdownSeconds };
