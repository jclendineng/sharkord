import type { TServerInfo } from '@sharkord/shared';
import { afterEach, describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { login } from '../../__tests__/helpers';
import { tdb, testsBaseUrl } from '../../__tests__/setup';
import { config } from '../../config';
import { invites, users } from '../../db/schema';
import { resolveOidcUser } from '../oidc/user';

// config.ini's registration.inviteOnly, which holds over the settings screen's allow new users
afterEach(() => {
  config.registration.inviteOnly = false;
});

describe('registration.inviteOnly', () => {
  test('should refuse a sign up without an invite even with new users allowed', async () => {
    config.registration.inviteOnly = true;

    const response = await login('uninvited', 'password123');

    expect(response.status).toBe(400);

    const created = await tdb
      .select({ id: users.id })
      .from(users)
      .where(eq(users.identity, 'uninvited'))
      .get();

    expect(created).toBeUndefined();
  });

  test('should still take a sign up with a valid invite', async () => {
    config.registration.inviteOnly = true;

    await tdb.insert(invites).values({
      code: 'INIINVITE',
      creatorId: 1,
      maxUses: 1,
      uses: 0,
      expiresAt: Date.now() + 86_400_000,
      createdAt: Date.now()
    });

    const response = await login('invited', 'password123', 'INIINVITE');

    expect(response.status).toBe(200);
  });

  test('should still let existing members log in', async () => {
    config.registration.inviteOnly = true;

    const response = await login('testowner', 'password123');

    expect(response.status).toBe(200);
  });

  test('should tell the apps registration is closed', async () => {
    config.registration.inviteOnly = true;

    const response = await fetch(`${testsBaseUrl}/info`);
    const data = (await response.json()) as TServerInfo;

    expect(data.allowNewUsers).toBe(false);
  });

  test('should refuse a new single sign on account', async () => {
    config.registration.inviteOnly = true;

    await expect(
      resolveOidcUser(
        {
          sub: 'new-subject',
          iss: 'https://idp.example.com',
          email: 'newperson@example.com',
          email_verified: true,
          preferred_username: 'newperson'
        },
        { userInfoFailed: false }
      )
    ).rejects.toThrow('new user registrations are disabled');
  });
});
