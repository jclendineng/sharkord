import type { IRootState } from '@/features/store';
import { describe, expect, test } from 'bun:test';
import { currentVoiceChannelIdSelector } from '../channels/selectors';
import {
  connectedSelector,
  disconnectInfoSelector,
  reconnectingSelector,
  reconnectSelector,
  restoredFromSnapshotSelector
} from '../selectors';
import type { TConnectionState, TVoiceSession } from '../types';

const withConnection = (connection: TConnectionState) =>
  ({ server: { connection } }) as unknown as IRootState;

const withVoice = (voiceSession: TVoiceSession) =>
  ({ server: { voiceSession } }) as unknown as IRootState;

describe('connection selectors', () => {
  test('should show the server inert only on the way back to it', () => {
    const reconnecting = (connection: TConnectionState) =>
      reconnectingSelector(withConnection(connection));

    expect(reconnecting({ kind: 'signedOut' })).toBe(false);
    expect(reconnecting({ kind: 'connected' })).toBe(false);
    expect(reconnecting({ kind: 'restoring' })).toBe(true);
    expect(
      reconnecting({ kind: 'reconnecting', attempt: 1, nextAttemptAt: null })
    ).toBe(true);
    expect(
      reconnecting({ kind: 'needsServerPassword', resumesFrom: 'signIn' })
    ).toBe(false);
    expect(
      reconnecting({ kind: 'needsServerPassword', resumesFrom: 'reconnect' })
    ).toBe(true);
  });

  test('should count a snapshot as restored until the password is answered', () => {
    const restored = (connection: TConnectionState) =>
      restoredFromSnapshotSelector(withConnection(connection));

    expect(restored({ kind: 'restoring' })).toBe(true);
    expect(
      restored({ kind: 'needsServerPassword', resumesFrom: 'restore' })
    ).toBe(true);
    expect(
      restored({ kind: 'needsServerPassword', resumesFrom: 'reconnect' })
    ).toBe(false);
  });

  test('should expose each state only while it is current', () => {
    const disconnectInfo = {
      code: 1006,
      reason: '',
      wasClean: false,
      time: new Date(0)
    };

    expect(connectedSelector(withConnection({ kind: 'connected' }))).toBe(true);
    expect(
      disconnectInfoSelector(
        withConnection({ kind: 'signedOut', disconnectInfo })
      )
    ).toBe(disconnectInfo);
    expect(reconnectSelector(withConnection({ kind: 'connected' }))).toBeNull();
  });
});

describe('currentVoiceChannelIdSelector', () => {
  test('should name the channel only while a call is live or being joined', () => {
    const channel = (voiceSession: TVoiceSession) =>
      currentVoiceChannelIdSelector(withVoice(voiceSession));

    expect(channel({ phase: 'idle' })).toBeUndefined();
    expect(channel({ phase: 'joining', channelId: 3 })).toBe(3);
    expect(channel({ phase: 'connecting', channelId: 3 })).toBe(3);
    expect(channel({ phase: 'inCall', channelId: 3 })).toBe(3);
    expect(channel({ phase: 'awaitingRejoin', channelId: 3 })).toBeUndefined();
    expect(channel({ phase: 'rejoinReady', channelId: 3 })).toBeUndefined();
    expect(channel({ phase: 'takenOver', channelId: 3 })).toBeUndefined();
  });
});
