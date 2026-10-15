import { describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb, testsBaseUrl } from '../../__tests__/setup';
import { loginLinks, sessions } from '../../db/schema';

type TLinkResponse = {
  status?: string;
  claimKey?: string;
  token?: string;
  errors?: Record<string, string>;
};

// the new device's side, asking the server with the qr code's token
const scan = async (token: string, claimKey?: string) => {
  const response = await fetch(`${testsBaseUrl}/login/link`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': 'Sharkord/1.0 (iPad; iPadOS 27.2)'
    },
    body: JSON.stringify({ token, claimKey })
  });

  return {
    status: response.status,
    body: (await response.json()) as TLinkResponse
  };
};

describe('signing in another device with a qr code', () => {
  test('should sign the new device in once the other one approves it', async () => {
    const { caller } = await initTest(1);
    const link = await caller.sessions.createLoginLink();

    const claim = await scan(link.token);

    expect(claim.status).toBe(202);
    expect(claim.body.claimKey).toBeString();

    const seen = await caller.sessions.getLoginLink({ id: link.id });

    expect(seen.status).toBe('claimed');

    const waiting = await scan(link.token, claim.body.claimKey);

    expect(waiting.status).toBe(202);
    expect(waiting.body.status).toBe('pending');

    await caller.sessions.approveLoginLink({ id: link.id, approve: true });

    const before = await tdb
      .select()
      .from(sessions)
      .where(eq(sessions.userId, 1));
    const done = await scan(link.token, claim.body.claimKey);
    const after = await tdb
      .select()
      .from(sessions)
      .where(eq(sessions.userId, 1));

    expect(done.status).toBe(200);
    expect(done.body.token).toBeString();
    expect(after.length).toBe(before.length + 1);
    // used once, then gone
    expect(await tdb.select().from(loginLinks)).toHaveLength(0);
  });

  test('should not hand the session to anyone without the claim key', async () => {
    const { caller } = await initTest(1);
    const link = await caller.sessions.createLoginLink();

    await scan(link.token);
    await caller.sessions.approveLoginLink({ id: link.id, approve: true });

    const stranger = await scan(link.token);

    expect(stranger.status).toBe(400);
    expect(JSON.stringify(stranger.body)).toContain(
      'Another device already scanned this code'
    );
  });

  test('should turn the device away when the other one declines', async () => {
    const { caller } = await initTest(1);
    const link = await caller.sessions.createLoginLink();
    const claim = await scan(link.token);

    await caller.sessions.approveLoginLink({ id: link.id, approve: false });

    const declined = await scan(link.token, claim.body.claimKey);

    expect(declined.status).toBe(400);
    expect(JSON.stringify(declined.body)).toContain('declined');
  });

  test('should refuse a wrong or run out code', async () => {
    const { caller } = await initTest(1);
    const link = await caller.sessions.createLoginLink();

    expect((await scan(`${link.id}.wrong`)).status).toBe(400);

    await tdb.update(loginLinks).set({ expiresAt: Date.now() - 1 });

    const expired = await scan(link.token);

    expect(expired.status).toBe(400);
    expect(JSON.stringify(expired.body)).toContain('run out');
    expect((await caller.sessions.getLoginLink({ id: link.id })).status).toBe(
      'expired'
    );
  });

  test('should replace an older code with a new one', async () => {
    const { caller } = await initTest(1);
    const first = await caller.sessions.createLoginLink();

    await caller.sessions.createLoginLink();

    expect((await scan(first.token)).status).toBe(400);
  });

  test('should not approve before a device scanned it', async () => {
    const { caller } = await initTest(1);
    const link = await caller.sessions.createLoginLink();

    await expect(
      caller.sessions.approveLoginLink({ id: link.id, approve: true })
    ).rejects.toThrow('No device has scanned that code yet.');
  });

  test('should not let someone else see or approve a code', async () => {
    const { caller } = await initTest(1);
    const { caller: otherCaller } = await initTest(2);
    const link = await caller.sessions.createLoginLink();

    await scan(link.token);

    await expect(
      otherCaller.sessions.getLoginLink({ id: link.id })
    ).rejects.toThrow('That sign in code is gone. Show a new one.');
    await expect(
      otherCaller.sessions.approveLoginLink({ id: link.id, approve: true })
    ).rejects.toThrow('That sign in code is gone. Show a new one.');
  });

  test('should refuse to approve a code that ran out', async () => {
    const { caller } = await initTest(1);
    const link = await caller.sessions.createLoginLink();

    await scan(link.token);
    await tdb.update(loginLinks).set({ expiresAt: Date.now() - 1 });

    await expect(
      caller.sessions.approveLoginLink({ id: link.id, approve: true })
    ).rejects.toThrow('That sign in code has run out. Show a new one.');
  });
});
