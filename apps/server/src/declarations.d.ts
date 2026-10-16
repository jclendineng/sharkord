import 'ws';

declare module 'ws' {
  interface WebSocket {
    userId?: number;
    token: string;
    // the login this socket belongs to, closed when that session is signed out
    sessionId?: string;
    // the socket that joined voice, which leaves it when it closes even if other tabs stay
    inVoice?: boolean;
  }
}

type TCommandMap = {
  [pluginId: string]: {
    [commandName: string]: TCommand;
  };
};

type TCommand = (...args: unknown[]) => Promise<unknown> | unknown;

declare global {
  interface Window {
    __plugins?: {
      commands: TCommandMap;
    };
  }
  // eslint-disable-next-line no-var
  var disableRateLimiting: boolean | undefined;
}

declare module 'bun' {
  interface Env {
    // SHARKORD_ prefixed environment variables
    SHARKORD_PORT?: string;
    SHARKORD_DEBUG?: string;
    SHARKORD_AUTOUPDATE?: string;
    SHARKORD_WEBRTC_PORT?: string;
    SHARKORD_WEBRTC_ANNOUNCED_ADDRESS?: string;
    SHARKORD_DATA_PATH?: string;
  }
}

declare module 'node:fs/promises' {
  export function exists(path: import('node:fs').PathLike): Promise<boolean>;
}

declare module 'fs/promises' {
  export function exists(path: import('node:fs').PathLike): Promise<boolean>;
}
