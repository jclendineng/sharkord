import { ServerEvents, StreamKind } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';
import {
  createFakeSocket,
  getSessionCaller,
  initTest
} from '../../__tests__/helpers';
import { VoiceRuntime } from '../../runtimes/voice';
import { pubsub } from '../pubsub';
import { getOnlineUserIds, handleSocketClose } from '../wss';

const connectTab = async (userId: number) => {
  const socket = createFakeSocket();

  await initTest(userId, { socket });

  return socket;
};

const VOICE_CHANNEL_ID = 2;

const JOIN_INPUT = {
  channelId: VOICE_CHANNEL_ID,
  state: { micMuted: false, soundMuted: false }
};

const connectVoiceTab = async (userId: number) => {
  const socket = createFakeSocket();
  const { caller } = await initTest(userId, { socket });

  return { socket, caller };
};

describe('presence across a user session', () => {
  test('should keep a user online until their last tab closes', async () => {
    const firstTab = await connectTab(2);
    const secondTab = await connectTab(2);

    expect(getOnlineUserIds()).toContain(2);

    await handleSocketClose(firstTab);

    expect(getOnlineUserIds()).toContain(2);

    await handleSocketClose(secondTab);

    expect(getOnlineUserIds()).not.toContain(2);
  });

  test('should announce the user left once, on the last tab', async () => {
    const firstTab = await connectTab(2);
    const secondTab = await connectTab(2);

    const departures: number[] = [];

    const subscription = pubsub.subscribe(ServerEvents.USER_LEAVE).subscribe({
      next: (userId) => {
        departures.push(userId);
      }
    });

    await handleSocketClose(firstTab);

    expect(departures).toEqual([]);

    await handleSocketClose(secondTab);

    subscription.unsubscribe();

    expect(departures).toEqual([2]);
  });
});

describe('voice across a user session', () => {
  test('should leave voice when the tab in it closes while another stays', async () => {
    const runtime = new VoiceRuntime(VOICE_CHANNEL_ID);

    await runtime.init();

    try {
      const phone = await connectVoiceTab(1);
      const desktop = await connectVoiceTab(1);

      await phone.caller.voice.join(JOIN_INPUT);

      const departures: number[] = [];

      const subscription = pubsub
        .subscribe(ServerEvents.USER_LEAVE_VOICE)
        .subscribe({
          next: ({ userId }) => {
            departures.push(userId);
          }
        });

      await handleSocketClose(phone.socket);

      subscription.unsubscribe();

      expect(runtime.getUser(1)).toBeUndefined();
      expect(departures).toEqual([1]);
      expect(getOnlineUserIds()).toContain(1);

      // the tab still connected can join again
      const result = await desktop.caller.voice.join(JOIN_INPUT);

      expect(result.routerRtpCapabilities).toBeDefined();
      expect(runtime.getUser(1)).toBeDefined();
    } finally {
      await runtime.destroy();
    }
  });

  test('should stay in voice when a tab that is not in it closes', async () => {
    const runtime = new VoiceRuntime(VOICE_CHANNEL_ID);

    await runtime.init();

    try {
      const phone = await connectVoiceTab(1);
      const desktop = await connectVoiceTab(1);

      await phone.caller.voice.join(JOIN_INPUT);
      await handleSocketClose(desktop.socket);

      expect(runtime.getUser(1)).toBeDefined();
    } finally {
      await runtime.destroy();
    }
  });

  test('should not leave voice on close after leaving it on that tab', async () => {
    const runtime = new VoiceRuntime(VOICE_CHANNEL_ID);

    await runtime.init();

    try {
      const phone = await connectVoiceTab(1);
      const desktop = await connectVoiceTab(1);

      await phone.caller.voice.join(JOIN_INPUT);
      await phone.caller.voice.leave();
      await desktop.caller.voice.join(JOIN_INPUT);
      await handleSocketClose(phone.socket);

      expect(runtime.getUser(1)).toBeDefined();
    } finally {
      await runtime.destroy();
    }
  });
});

describe('voice taken over by another connection of the account', () => {
  // the seeded private voice channel, which user 1 joins as the owner
  const OTHER_VOICE_CHANNEL_ID = 4;

  const watchDepartures = () => {
    const departures: {
      channelId: number;
      userId: number;
      takenOver?: boolean;
    }[] = [];
    const subscription = pubsub
      .subscribe(ServerEvents.USER_LEAVE_VOICE)
      .subscribe({
        next: (event) => {
          departures.push(event);
        }
      });

    return { departures, stop: () => subscription.unsubscribe() };
  };

  test('should hand the seat to the same login rejoining on a new socket', async () => {
    const runtime = new VoiceRuntime(VOICE_CHANNEL_ID);

    await runtime.init();

    try {
      const oldSocket = createFakeSocket();
      const old = await getSessionCaller(1, oldSocket);

      await old.caller.voice.join(JOIN_INPUT);

      const fresh = await getSessionCaller(1, createFakeSocket(), old.token);
      const { departures, stop } = watchDepartures();

      const result = await fresh.caller.voice.join(JOIN_INPUT);

      stop();

      expect(result.routerRtpCapabilities).toBeDefined();
      expect(runtime.getUser(1)).toBeDefined();
      expect(departures).toEqual([
        { channelId: VOICE_CHANNEL_ID, userId: 1, takenOver: true }
      ]);

      // the dead socket going later leaves the new seat alone
      await handleSocketClose(oldSocket);

      expect(runtime.getUser(1)).toBeDefined();
    } finally {
      await runtime.destroy();
    }
  });

  test('should hand the seat to another device of the account, in another channel', async () => {
    const runtime = new VoiceRuntime(VOICE_CHANNEL_ID);
    const otherRuntime = new VoiceRuntime(OTHER_VOICE_CHANNEL_ID);

    await runtime.init();
    await otherRuntime.init();

    try {
      const phone = await getSessionCaller(1, createFakeSocket());
      const desktop = await getSessionCaller(1, createFakeSocket());

      await phone.caller.voice.join(JOIN_INPUT);

      const { departures, stop } = watchDepartures();

      await desktop.caller.voice.join({
        ...JOIN_INPUT,
        channelId: OTHER_VOICE_CHANNEL_ID
      });

      stop();

      expect(runtime.getUser(1)).toBeUndefined();
      expect(otherRuntime.getUser(1)).toBeDefined();
      expect(departures).toEqual([
        { channelId: VOICE_CHANNEL_ID, userId: 1, takenOver: true }
      ]);
    } finally {
      await runtime.destroy();
      await otherRuntime.destroy();
    }
  });

  test('should let the first device take the seat back', async () => {
    const runtime = new VoiceRuntime(VOICE_CHANNEL_ID);

    await runtime.init();

    try {
      const phone = await getSessionCaller(1, createFakeSocket());
      const desktop = await getSessionCaller(1, createFakeSocket());

      await phone.caller.voice.join(JOIN_INPUT);
      await desktop.caller.voice.join(JOIN_INPUT);

      const result = await phone.caller.voice.join(JOIN_INPUT);

      expect(result.routerRtpCapabilities).toBeDefined();
      expect(runtime.getUser(1)).toBeDefined();
    } finally {
      await runtime.destroy();
    }
  });

  test('should refuse voice requests from the socket that lost its seat', async () => {
    const runtime = new VoiceRuntime(VOICE_CHANNEL_ID);

    await runtime.init();

    try {
      const phone = await getSessionCaller(1, createFakeSocket());
      const desktop = await getSessionCaller(1, createFakeSocket());

      await phone.caller.voice.join(JOIN_INPUT);
      await desktop.caller.voice.join(JOIN_INPUT);

      await expect(phone.caller.voice.leave()).rejects.toThrow(
        'User is not in a voice channel'
      );
      // ignored, rather than closing a stream of the desktop's
      await phone.caller.voice.closeProducer({ kind: StreamKind.AUDIO });

      // the desktop's seat is untouched
      expect(runtime.getUser(1)).toBeDefined();
    } finally {
      await runtime.destroy();
    }
  });
});
