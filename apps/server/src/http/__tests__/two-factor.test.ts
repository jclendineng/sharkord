import { TOTP_REQUIRED_MESSAGE } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest, login } from '../../__tests__/helpers';
import { tdb, testsBaseUrl } from '../../__tests__/setup';
import { users, userTotp } from '../../db/schema';
import { getTotpCode, getTotpStep } from '../../utils/totp';

// seeded user 2 "testuser" signs in with password123
const loginWithCode = (totp?: string) =>
  fetch(`${testsBaseUrl}/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      identity: 'testuser',
      password: 'password123',
      totp
    })
  });

const enableTwoFactor = async () => {
  const { caller } = await initTest(2);
  const { secret, uri } = await caller.users.startTwoFactor();
  const { recoveryCodes } = await caller.users.confirmTwoFactor({
    code: getTotpCode(secret, getTotpStep())
  });

  return { caller, secret, uri, recoveryCodes };
};

const loginErrors = async (response: Response) =>
  ((await response.json()) as { errors?: Record<string, string> }).errors;

describe('two-factor authentication', () => {
  test('should set up with a confirming code and give recovery codes', async () => {
    const { caller, uri, recoveryCodes } = await enableTwoFactor();

    expect(uri).toStartWith('otpauth://totp/');
    expect(recoveryCodes).toHaveLength(8);
    expect(await caller.users.getTwoFactor()).toEqual({ enabled: true });
  });

  test('should refuse a wrong confirming code', async () => {
    const { caller } = await initTest(2);

    await caller.users.startTwoFactor();

    await expect(
      caller.users.confirmTwoFactor({ code: '000000' })
    ).rejects.toThrow("That code isn't right. Check the time on your device.");
    expect(await caller.users.getTwoFactor()).toEqual({ enabled: false });
  });

  test('should ask for the code after the right password, then sign in with it', async () => {
    const { secret } = await enableTwoFactor();

    // the confirming code used the current step, so the next one is what an app shows later
    const withoutCode = await loginWithCode();
    const withCode = await loginWithCode(
      getTotpCode(secret, getTotpStep() + 1)
    );

    expect(withoutCode.status).toBe(400);
    expect((await loginErrors(withoutCode))?.totp).toBe(TOTP_REQUIRED_MESSAGE);
    expect(withCode.status).toBe(200);
  });

  test('should not ask for a code after a wrong password', async () => {
    await enableTwoFactor();

    const response = await login('testuser', 'wrong-password');

    expect((await loginErrors(response))?.totp).toBeUndefined();
  });

  test('should refuse a code used twice', async () => {
    const { secret } = await enableTwoFactor();
    const code = getTotpCode(secret, getTotpStep() + 1);

    expect((await loginWithCode(code)).status).toBe(200);
    expect((await loginWithCode(code)).status).toBe(400);
  });

  test('should take a recovery code once', async () => {
    const { recoveryCodes } = await enableTwoFactor();

    expect((await loginWithCode(recoveryCodes[0])).status).toBe(200);
    expect((await loginWithCode(recoveryCodes[0])).status).toBe(400);
  });

  test('should turn off only with a code', async () => {
    const { caller, secret } = await enableTwoFactor();

    await expect(
      caller.users.disableTwoFactor({ code: '000000' })
    ).rejects.toThrow("That code isn't right.");

    await caller.users.disableTwoFactor({
      code: getTotpCode(secret, getTotpStep() + 1)
    });

    expect(await tdb.select().from(userTotp)).toEqual([]);
  });

  test('should refuse setup on an sso account', async () => {
    await tdb.update(users).set({ passwordSet: false }).where(eq(users.id, 2));

    const { caller } = await initTest(2);

    await expect(caller.users.startTwoFactor()).rejects.toThrow(
      'This account signs in through an identity provider, turn on two-factor authentication there.'
    );
  });

  test('should be turned off by a moderator password reset', async () => {
    await enableTwoFactor();

    const { caller: owner } = await initTest(1);
    const { token } = await owner.users.createPasswordReset({ userId: 2 });

    await fetch(`${testsBaseUrl}/password-reset`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, password: 'password123' })
    });

    expect(await tdb.select().from(userTotp)).toEqual([]);
  });
});
