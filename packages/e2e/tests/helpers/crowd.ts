import {
  TYPING_MS,
  type AppRouter,
  type TJoinedMessage
} from '@sharkord/shared';
import { createTRPCProxyClient, createWSClient, wsLink } from '@trpc/client';

const SERVER_HTTP_URL = 'http://localhost:4991';
const SERVER_WS_URL = 'ws://localhost:4991';
const CROWD_PASSWORD = 'password123';

const crowdName = (index: number) =>
  `Crowd ${String(index + 1).padStart(3, '0')}`;

// every member signs in from an address of its own, the way a hundred people would. the server
// trusts x-forwarded-for from localhost, so each one gets its own login rate limit bucket
// instead of the fifth sign in from 127.0.0.1 being turned away. the identity does not exist
// yet, and the seeded server allows new users, so this is also the member registering
const signIn = async (index: number): Promise<string> => {
  const response = await fetch(`${SERVER_HTTP_URL}/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Forwarded-For': `198.51.100.${index + 1}`
    },
    body: JSON.stringify({
      identity: `crowd${index}`,
      password: CROWD_PASSWORD
    })
  });

  if (!response.ok) {
    throw new Error(
      `${crowdName(index)} could not sign in: ${response.status} ${await response.text()}`
    );
  }

  const { token } = (await response.json()) as { token: string };

  return token;
};

// the same handshake, join and subscription the web client makes, minus the browser. the
// subscription is only resolved once the server has started it, so a message sent right
// after this returns cannot slip past a member who has not started listening yet
const connect = async (
  token: string,
  onMessage: (message: TJoinedMessage) => void
) => {
  const wsClient = createWSClient({
    url: SERVER_WS_URL,
    connectionParams: { token }
  });

  const trpc = createTRPCProxyClient<AppRouter>({
    links: [wsLink({ client: wsClient })]
  });

  const { handshakeHash } = await trpc.others.handshake.query();
  const data = await trpc.others.joinServer.query({ handshakeHash });

  await new Promise<void>((resolve, reject) => {
    trpc.messages.onNew.subscribe(undefined, {
      onStarted: () => resolve(),
      onData: onMessage,
      onError: reject
    });
  });

  return { wsClient, trpc, data, closed: false };
};

// a chat member without a browser, so a hundred of them fit next to the few real pages
// that watch the ui. everything it is sent is kept in `received` for the spec to count
const joinCrowdMember = async (index: number) => {
  const name = crowdName(index);
  const token = await signIn(index);
  const received: TJoinedMessage[] = [];
  const failures: unknown[] = [];

  const onMessage = (message: TJoinedMessage) => {
    received.push(message);
  };

  let session = await connect(token, onMessage);

  // named after joining, like someone filling in their profile on first launch. every page
  // already connected gets the rename live, which is part of what the spec checks
  await session.trpc.users.update.mutate({ name, profileColor: '#3b82f6' });

  const userId = session.data.ownUserId;

  const channelIdByName = (channelName: string) => {
    const channel = session.data.channels.find(
      (candidate) => candidate.name === channelName
    );

    if (!channel) {
      throw new Error(`${name} cannot see a channel named ${channelName}`);
    }

    return channel.id;
  };

  // signals as often as the web client's throttle lets it, which is what keeps a typer in
  // everyone's indicator. returns the function that stops typing
  const startTyping = (channelId: number) => {
    const signal = async () => {
      const current = session;

      try {
        await current.trpc.messages.signalTyping.mutate({ channelId });
      } catch (error) {
        // a signal still in flight when the member hangs up on purpose fails with it, which
        // is not the server refusing anything
        if (!current.closed) failures.push(error);
      }
    };

    signal();

    const timer = setInterval(signal, TYPING_MS);

    return () => clearInterval(timer);
  };

  const send = (channelId: number, text: string) =>
    session.trpc.messages.send.mutate({ channelId, content: `<p>${text}</p>` });

  const disconnect = () => {
    session.closed = true;
    session.wsClient.close();
  };

  const reconnect = async () => {
    session = await connect(token, onMessage);
  };

  return {
    index,
    name,
    userId,
    received,
    failures,
    channelIdByName,
    startTyping,
    send,
    disconnect,
    reconnect
  };
};

type TCrowdMember = Awaited<ReturnType<typeof joinCrowdMember>>;

export { crowdName, joinCrowdMember, type TCrowdMember };
