import { describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest, login } from '../../__tests__/helpers';
import { tdb, testsBaseUrl } from '../../__tests__/setup';
import { passwordResets, users } from '../../db/schema';

// seeded: user 1 the owner, user 2 "testuser" with password123, user 5 a moderator holding
// MANAGE_USERS but not the owner role
const redeem = (token: string, password: string) =>
  fetch(`${testsBaseUrl}/password-reset`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token, password })
  });

describe('password resets', () => {
  test('should set a new password from a link and sign every session out', async () => {
    const { caller } = await initTest(1);
    const before = await tdb
      .select({ tokenVersion: users.tokenVersion })
      .from(users)
      .where(eq(users.id, 2))
      .get();

    const { token } = await caller.users.createPasswordReset({ userId: 2 });
    const response = await redeem(token, 'brand-new-password');

    const after = await tdb
      .select({ tokenVersion: users.tokenVersion })
      .from(users)
      .where(eq(users.id, 2))
      .get();
    const oldLogin = await login('testuser', 'password123');
    const newLogin = await login('testuser', 'brand-new-password');

    expect(response.status).toBe(200);
    expect(after!.tokenVersion).toBe(before!.tokenVersion + 1);
    expect(oldLogin.status).toBe(400);
    expect(newLogin.status).toBe(200);
    expect(await tdb.select().from(passwordResets)).toEqual([]);
  });

  test('should refuse a link used twice, replaced or expired', async () => {
    const { caller } = await initTest(1);

    const first = await caller.users.createPasswordReset({ userId: 2 });
    const second = await caller.users.createPasswordReset({ userId: 2 });

    // the newer link replaced the first
    expect((await redeem(first.token, 'another-password')).status).toBe(400);
    expect((await redeem(second.token, 'another-password')).status).toBe(200);
    expect((await redeem(second.token, 'third-password')).status).toBe(400);

    const expiring = await caller.users.createPasswordReset({ userId: 2 });

    await tdb.update(passwordResets).set({ expiresAt: Date.now() - 1 });

    expect((await redeem(expiring.token, 'late-password')).status).toBe(400);
  });

  test('should refuse a password that is too short', async () => {
    const { caller } = await initTest(1);
    const { token } = await caller.users.createPasswordReset({ userId: 2 });

    expect((await redeem(token, 'abc')).status).toBe(400);
  });

  test('should refuse someone without MANAGE_USERS', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.users.createPasswordReset({ userId: 3 })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should refuse a reset for the owner from a moderator', async () => {
    const { caller } = await initTest(5);

    await expect(
      caller.users.createPasswordReset({ userId: 1 })
    ).rejects.toThrow(
      'Only users with the owner role can act on the server owner.'
    );
  });

  test('should say when the account does not exist', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.users.createPasswordReset({ userId: 999 })
    ).rejects.toThrow('User not found.');
  });
});
