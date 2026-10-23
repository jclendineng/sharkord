import { useIsConnected } from '@/features/server/hooks';
import { useEffect, useRef } from 'react';

// runs when the connection comes back after a drop, never on the first join. nothing is
// delivered while the socket is down, so this is where a view catches up on what it missed
const useOnReconnect = (callback: () => void) => {
  const connected = useIsConnected();
  const wasConnected = useRef(connected);

  useEffect(() => {
    const reconnected = connected && !wasConnected.current;

    wasConnected.current = connected;

    if (reconnected) callback();
  }, [connected, callback]);
};

export { useOnReconnect };
