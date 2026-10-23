import type { BrowserContext } from '@playwright/test';

type TLinkProfile = {
  latencyMs: number;
  jitterMs: number;
  kbps: number;
};

const LINK_PROFILES = {
  mobile: { latencyMs: 150, jitterMs: 80, kbps: 1_500 },
  congested: { latencyMs: 400, jitterMs: 250, kbps: 400 }
} satisfies Record<string, TLinkProfile>;

// only the app's socket to the server, not vite's hot reload socket on the client port
const SERVER_SOCKET = /localhost:4991/;

// one direction of the link. a websocket rides on tcp, so a frame that is held up holds back
// every frame behind it instead of being overtaken, and a large frame takes its time to
// cross a slow link. jitter therefore delays delivery but never reorders it
const createLane = ({ latencyMs, jitterMs, kbps }: TLinkProfile) => {
  let busyUntil = 0;

  return (size: number, deliver: () => void) => {
    const arrivesAt = Date.now() + latencyMs + Math.random() * jitterMs;

    busyUntil = Math.max(busyUntil, arrivesAt) + (size * 8) / kbps;

    setTimeout(deliver, busyUntil - Date.now());
  };
};

// shapes the page's real socket to the server, including every socket a reconnect opens.
// frames are delayed here rather than with devtools throttling so the order guarantee above
// holds and the spec can drop the connection at a moment of its choosing
const shapeLink = async (context: BrowserContext, profile: TLinkProfile) => {
  let cutCurrent: (() => Promise<void>) | undefined;

  await context.routeWebSocket(SERVER_SOCKET, (ws) => {
    const server = ws.connectToServer();
    const up = createLane(profile);
    const down = createLane(profile);
    let isCut = false;

    ws.onMessage((message) => {
      up(message.length, () => {
        if (!isCut) server.send(message);
      });
    });

    server.onMessage((message) => {
      down(message.length, () => {
        if (!isCut) ws.send(message);
      });
    });

    // the connection drops the way a phone losing signal does: the page sees an unclean
    // close and has to find its own way back, and frames still in flight are lost
    cutCurrent = async () => {
      isCut = true;
      await ws.close({ code: 4000, reason: 'network drop' });
    };
  });

  const cut = async () => {
    await cutCurrent?.();
  };

  return { cut };
};

type TLink = Awaited<ReturnType<typeof shapeLink>>;

export { LINK_PROFILES, shapeLink, type TLink, type TLinkProfile };
