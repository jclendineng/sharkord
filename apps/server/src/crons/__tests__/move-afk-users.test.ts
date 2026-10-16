import { ServerEvents } from '@sharkord/shared';
import { describe, expect, spyOn, test } from 'bun:test';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { settings } from '../../db/schema';
import { VoiceRuntime } from '../../runtimes/voice';
import { pubsub } from '../../utils/pubsub';
import { moveAfkUsers } from '../move-afk-users';

// seeded voice channels: Voice (2) for the call, Private Voice (4) as the afk channel, and the
// dm channel (3) between users 3 and 4
const VOICE_CHANNEL_ID = 2;
const AFK_CHANNEL_ID = 4;
const DM_CHANNEL_ID = 3;
const TEN_MINUTES_MS = 10 * 60 * 1000;

const collectMoves = (userId: number) => {
  const moves: { channelId: number; fromChannelId: number }[] = [];

  const subscription = pubsub
    .subscribeFor(userId, ServerEvents.USER_VOICE_MOVED)
    .subscribe({
      next: (move) => {
        moves.push(move);
      }
    });

  return { moves, stop: () => subscription.unsubscribe() };
};

const skipAhead = (ms: number) => {
  const now = Date.now();

  spyOn(Date, 'now').mockReturnValue(now + ms);
};

describe('moveAfkUsers', () => {
  test('should move someone silent past the timeout into the afk channel', async () => {
    await tdb.update(settings).set({ afkChannelId: AFK_CHANNEL_ID });

    const runtime = new VoiceRuntime(VOICE_CHANNEL_ID);

    runtime.addUser(2, { micMuted: false, soundMuted: false });

    const { moves, stop } = collectMoves(2);

    try {
      skipAhead(TEN_MINUTES_MS);

      await moveAfkUsers();

      expect(moves).toEqual([
        { channelId: AFK_CHANNEL_ID, fromChannelId: VOICE_CHANNEL_ID }
      ]);
    } finally {
      stop();
      await runtime.destroy();
    }
  });

  test('should leave someone active within the timeout', async () => {
    await tdb.update(settings).set({ afkChannelId: AFK_CHANNEL_ID });

    const runtime = new VoiceRuntime(VOICE_CHANNEL_ID);

    runtime.addUser(2, { micMuted: false, soundMuted: false });

    const { moves, stop } = collectMoves(2);

    try {
      skipAhead(60 * 1000);

      await moveAfkUsers();

      expect(moves).toEqual([]);
    } finally {
      stop();
      await runtime.destroy();
    }
  });

  test('should do nothing without an afk channel', async () => {
    const runtime = new VoiceRuntime(VOICE_CHANNEL_ID);

    runtime.addUser(2, { micMuted: false, soundMuted: false });

    const { moves, stop } = collectMoves(2);

    try {
      skipAhead(TEN_MINUTES_MS);

      await moveAfkUsers();

      expect(moves).toEqual([]);
    } finally {
      stop();
      await runtime.destroy();
    }
  });

  test('should leave direct message calls and the afk channel itself alone', async () => {
    await tdb.update(settings).set({ afkChannelId: AFK_CHANNEL_ID });

    const dmRuntime = new VoiceRuntime(DM_CHANNEL_ID);
    const afkRuntime = new VoiceRuntime(AFK_CHANNEL_ID);

    dmRuntime.addUser(3, { micMuted: false, soundMuted: false });
    afkRuntime.addUser(2, { micMuted: false, soundMuted: false });

    const dmMoves = collectMoves(3);
    const afkMoves = collectMoves(2);

    try {
      skipAhead(TEN_MINUTES_MS);

      await moveAfkUsers();

      expect(dmMoves.moves).toEqual([]);
      expect(afkMoves.moves).toEqual([]);
    } finally {
      dmMoves.stop();
      afkMoves.stop();
      await dmRuntime.destroy();
      await afkRuntime.destroy();
    }
  });
});

describe('afk settings', () => {
  test('should save an afk voice channel and timeout', async () => {
    const { caller } = await initTest(1);

    await caller.others.updateSettings({
      afkChannelId: AFK_CHANNEL_ID,
      afkTimeoutSeconds: 900
    });

    const stored = await tdb
      .select({
        afkChannelId: settings.afkChannelId,
        afkTimeoutSeconds: settings.afkTimeoutSeconds
      })
      .from(settings)
      .get();

    expect(stored).toEqual({
      afkChannelId: AFK_CHANNEL_ID,
      afkTimeoutSeconds: 900
    });
  });

  test('should refuse a text or direct message channel', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.others.updateSettings({ afkChannelId: 1 })
    ).rejects.toThrow('The AFK channel has to be a voice channel.');
    await expect(
      caller.others.updateSettings({ afkChannelId: DM_CHANNEL_ID })
    ).rejects.toThrow('The AFK channel has to be a voice channel.');
  });

  test('should refuse a timeout outside the allowed range', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.others.updateSettings({ afkTimeoutSeconds: 30 })
    ).rejects.toThrow();
  });

  test('should refuse someone without MANAGE_SETTINGS', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.others.updateSettings({ afkChannelId: AFK_CHANNEL_ID })
    ).rejects.toThrow('Insufficient permissions');
  });
});
