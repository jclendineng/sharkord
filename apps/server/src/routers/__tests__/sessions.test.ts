import { DisconnectCode } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { createMockContext } from '../../__tests__/context';
import {
  createFakeSocket,
  getMockedToken,
  getSessionCaller,
  initTest,
  login,
  testPushKey
} from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { getUserByToken } from '../../db/queries/users';
import { pushDevices, sessions } from '../../db/schema';
import { getTokenSessionId } from '../../helpers/session-token';
import { SESSION_TOKEN_TTL_MS } from '../../helpers/sessions';
import { trackUserSocket } from '../../utils/wss';

const DEVICE_TOKEN = 'a'.repeat(64);

describe('sessions router', () => {
  test('should start a session when signing in with a password', async () => {
    const response = await login('testowner', 'password123', undefined, {
      'user-agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15'
    });
    const { token } = (await response.json()) as { token: string };
    const sessionId = getTokenSessionId(token);

    expect(sessionId).toBeDefined();

    const session = await tdb
      .select()
      .from(sessions)
      .where(eq(sessions.id, sessionId!))
      .get();

    expect(session?.userId).toBe(1);
    expect(session?.os).toContain('iOS');
  });

  test("should list the caller's own sessions and mark the current one", async () => {
    const { caller, sessionId } = await getSessionCaller(1);
    const { sessionId: otherDeviceId } = await getSessionCaller(1);

    await getSessionCaller(2);

    const list = await caller.sessions.getAll();

    expect(list.map(({ id }) => id).sort()).toEqual(
      [sessionId, otherDeviceId].sort()
    );
    expect(list.find(({ id }) => id === sessionId)?.isCurrent).toBe(true);
    expect(list.find(({ id }) => id === otherDeviceId)?.isCurrent).toBe(false);
  });

  test('should leave out sessions idle for longer than a token lives', async () => {
    const { caller } = await getSessionCaller(1);
    const { sessionId: staleId } = await getSessionCaller(1);

    await tdb
      .update(sessions)
      .set({ lastActiveAt: Date.now() - SESSION_TOKEN_TTL_MS - 1000 })
      .where(eq(sessions.id, staleId));

    const list = await caller.sessions.getAll();

    expect(list.map(({ id }) => id)).not.toContain(staleId);
  });

  test('should sign out another device, refuse its token and close its socket', async () => {
    const { caller } = await getSessionCaller(1);
    const socket = createFakeSocket();
    const { token: otherToken, sessionId: otherId } = await getSessionCaller(
      1,
      socket
    );

    trackUserSocket(1, socket);

    await caller.sessions.revoke({ sessionId: otherId });

    expect(await getUserByToken(otherToken)).toBeUndefined();
    expect(socket.closes).toEqual([
      {
        code: DisconnectCode.KICKED,
        reason: 'You were signed out of this device'
      }
    ]);
    await expect(
      createMockContext({ customToken: otherToken })
    ).rejects.toThrow('Invalid authentication token');
  });

  test("should not sign out someone else's device", async () => {
    const { caller } = await getSessionCaller(2);
    const { token: ownerToken, sessionId: ownerSessionId } =
      await getSessionCaller(1);

    await expect(
      caller.sessions.revoke({ sessionId: ownerSessionId })
    ).rejects.toThrow('That device is already signed out.');
    expect(await getUserByToken(ownerToken)).toBeDefined();
  });

  test('should reject an empty session id', async () => {
    const { caller } = await getSessionCaller(1);

    await expect(caller.sessions.revoke({ sessionId: '' })).rejects.toThrow();
  });

  test('should sign out every other device and keep the current one', async () => {
    const { caller, token, sessionId } = await getSessionCaller(1);
    const { token: otherToken } = await getSessionCaller(1);
    const { token: anotherToken } = await getSessionCaller(1);
    const { token: otherUserToken } = await getSessionCaller(2);

    const { revokedCount } = await caller.sessions.revokeOthers();

    expect(revokedCount).toBe(2);
    expect(await getUserByToken(token)).toBeDefined();
    expect(await getUserByToken(otherToken)).toBeUndefined();
    expect(await getUserByToken(anotherToken)).toBeUndefined();
    expect(await getUserByToken(otherUserToken)).toBeDefined();

    const remaining = await caller.sessions.getAll();

    expect(remaining.map(({ id }) => id)).toEqual([sessionId]);
  });

  test('should stop pushing to a device once its session is signed out', async () => {
    const { caller } = await getSessionCaller(1);
    const { caller: phone, sessionId: phoneSessionId } =
      await getSessionCaller(1);

    await phone.notifications.registerDevice({
      token: DEVICE_TOKEN,
      relayTicket: 'ticket',
      encryptionKey: testPushKey.encryptionKey
    });

    const registered = await tdb
      .select({ sessionId: pushDevices.sessionId })
      .from(pushDevices)
      .where(eq(pushDevices.token, DEVICE_TOKEN))
      .get();

    expect(registered?.sessionId).toBe(phoneSessionId);

    await caller.sessions.revoke({ sessionId: phoneSessionId });

    const afterRevoke = await tdb
      .select()
      .from(pushDevices)
      .where(eq(pushDevices.token, DEVICE_TOKEN))
      .all();

    expect(afterRevoke).toEqual([]);
  });

  test('should refresh a token for the same session', async () => {
    const { caller, sessionId } = await getSessionCaller(1);

    const { token } = await caller.sessions.refreshToken();

    expect(getTokenSessionId(token)).toBe(sessionId);
    expect((await getUserByToken(token))?.id).toBe(1);
  });

  test('should move a token from before sessions onto a session when refreshing', async () => {
    const { caller } = await initTest(1);

    const { token } = await caller.sessions.refreshToken();
    const sessionId = getTokenSessionId(token);

    expect(sessionId).toBeDefined();

    const session = await tdb
      .select({ userId: sessions.userId })
      .from(sessions)
      .where(eq(sessions.id, sessionId!))
      .get();

    expect(session?.userId).toBe(1);
  });

  test('should keep accepting a token from before sessions existed', async () => {
    const legacyToken = await getMockedToken(1);

    expect((await getUserByToken(legacyToken))?.id).toBe(1);
  });

  test('should forget every session when the password changes', async () => {
    const { caller } = await getSessionCaller(2);

    await getSessionCaller(2);

    await caller.users.updatePassword({
      currentPassword: 'password123',
      newPassword: 'password456',
      confirmNewPassword: 'password456'
    });

    const remaining = await tdb
      .select()
      .from(sessions)
      .where(eq(sessions.userId, 2))
      .all();

    expect(remaining).toEqual([]);
  });
});
