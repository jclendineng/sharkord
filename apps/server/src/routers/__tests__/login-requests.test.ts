import { describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb, testsBaseUrl } from '../../__tests__/setup';
import { loginRequests, sessions } from '../../db/schema';

type TRequestResponse = {
  id?: string;
  token?: string;
  pollKey?: string;
  status?: string;
  errors?: Record<string, string>;
};

// the side of the device without a camera: start a request, then ask after it
const ask = async (body: { id?: string; pollKey?: string } = {}) => {
  const response = await fetch(`${testsBaseUrl}/login/request`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': 'Sharkord/1.0 (Mac mini; macOS 27.2)'
    },
    body: JSON.stringify(body)
  });

  return {
    status: response.status,
    body: (await response.json()) as TRequestResponse
  };
};

const start = async () => {
  const { body } = await ask();

  return {
    id: body.id as string,
    token: body.token as string,
    pollKey: body.pollKey as string
  };
};

describe('signing in a device without a camera by its qr code', () => {
  test('should sign the asking device in once a signed in one approves it', async () => {
    const { caller } = await initTest(1);
    const request = await start();

    const shown = await caller.sessions.getLoginRequest({
      token: request.token
    });

    expect(shown.status).toBe('waiting');

    const waiting = await ask({ id: request.id, pollKey: request.pollKey });

    expect(waiting.status).toBe(202);
    expect(waiting.body.status).toBe('pending');

    await caller.sessions.approveLoginRequest({
      token: request.token,
      approve: true
    });

    const before = await tdb
      .select()
      .from(sessions)
      .where(eq(sessions.userId, 1));
    const done = await ask({ id: request.id, pollKey: request.pollKey });
    const after = await tdb
      .select()
      .from(sessions)
      .where(eq(sessions.userId, 1));

    expect(done.status).toBe(200);
    expect(done.body.token).toBeString();
    expect(after.length).toBe(before.length + 1);
    // collected once, then gone
    expect(await tdb.select().from(loginRequests)).toHaveLength(0);
  });

  test('should sign in as whoever approved it', async () => {
    const { caller } = await initTest(2);
    const request = await start();

    await caller.sessions.approveLoginRequest({
      token: request.token,
      approve: true
    });

    const before = await tdb
      .select()
      .from(sessions)
      .where(eq(sessions.userId, 2));

    await ask({ id: request.id, pollKey: request.pollKey });

    const after = await tdb
      .select()
      .from(sessions)
      .where(eq(sessions.userId, 2));

    expect(after.length).toBe(before.length + 1);
  });

  test('should not hand the session to anyone without the poll key', async () => {
    const { caller } = await initTest(1);
    const request = await start();

    await caller.sessions.approveLoginRequest({
      token: request.token,
      approve: true
    });

    // the qr code's secret is not the poll key
    const secret = request.token.split('.')[1];
    const stranger = await ask({ id: request.id, pollKey: secret });

    expect(stranger.status).toBe(400);
    expect(JSON.stringify(stranger.body)).toContain('run out');
  });

  test('should turn the device away when the request is declined', async () => {
    const { caller } = await initTest(1);
    const request = await start();

    await caller.sessions.approveLoginRequest({
      token: request.token,
      approve: false
    });

    const declined = await ask({ id: request.id, pollKey: request.pollKey });

    expect(declined.status).toBe(400);
    expect(JSON.stringify(declined.body)).toContain('declined');
    expect(await tdb.select().from(loginRequests)).toHaveLength(0);
  });

  test('should refuse a request that ran out', async () => {
    const { caller } = await initTest(1);
    const request = await start();

    await tdb.update(loginRequests).set({ expiresAt: Date.now() - 1 });

    const expired = await ask({ id: request.id, pollKey: request.pollKey });

    expect(expired.status).toBe(400);
    expect(JSON.stringify(expired.body)).toContain('run out');
    expect(
      (await caller.sessions.getLoginRequest({ token: request.token })).status
    ).toBe('expired');
    await expect(
      caller.sessions.approveLoginRequest({
        token: request.token,
        approve: true
      })
    ).rejects.toThrow('That sign in code has run out. Show a new one.');
  });

  test('should sweep away requests that ran out when a new one starts', async () => {
    await start();
    await tdb.update(loginRequests).set({ expiresAt: Date.now() - 1 });

    await start();

    expect(await tdb.select().from(loginRequests)).toHaveLength(1);
  });

  test('should refuse a token with a wrong secret', async () => {
    const { caller } = await initTest(1);
    const request = await start();

    await expect(
      caller.sessions.getLoginRequest({ token: `${request.id}.wrong` })
    ).rejects.toThrow('That sign in code is gone. Show a new one.');
    await expect(
      caller.sessions.approveLoginRequest({
        token: `${request.id}.wrong`,
        approve: true
      })
    ).rejects.toThrow('That sign in code is gone. Show a new one.');
  });

  test('should answer a request only once', async () => {
    const { caller } = await initTest(1);
    const { caller: otherCaller } = await initTest(2);
    const request = await start();

    await caller.sessions.approveLoginRequest({
      token: request.token,
      approve: true
    });

    await expect(
      otherCaller.sessions.approveLoginRequest({
        token: request.token,
        approve: true
      })
    ).rejects.toThrow('That sign in code was already answered.');
  });
});
