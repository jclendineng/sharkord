import { describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { tdb } from '../../../__tests__/setup';
import { pushDevices, sessions, users } from '../../../db/schema';
import { buildLoginPayload, getLoginNotificationDevices } from '../login';

// user 1 signed in on two devices with push, "old" and "new", the second just now
const signIn = async (sessionId: string, ticket: string) => {
  const user = await tdb
    .select({ tokenVersion: users.tokenVersion })
    .from(users)
    .where(eq(users.id, 1))
    .get();

  await tdb.insert(sessions).values({
    id: sessionId,
    userId: 1,
    createdAt: Date.now(),
    lastActiveAt: Date.now()
  });

  await tdb.insert(pushDevices).values({
    userId: 1,
    token: `${sessionId}-device`,
    tokenVersion: user!.tokenVersion,
    sessionId,
    relayTicket: ticket,
    encryptionKey: 'key',
    createdAt: Date.now()
  });
};

describe('new login notifications', () => {
  test('should go to every other device and not the one that signed in', async () => {
    await signIn('old', 'old-ticket');
    await signIn('new', 'new-ticket');

    const devices = await getLoginNotificationDevices(1, 'new');

    expect(devices.map(({ relayTicket }) => relayTicket)).toEqual([
      'old-ticket'
    ]);
  });

  test('should skip devices from before the sessions were ended', async () => {
    await signIn('old', 'old-ticket');
    await tdb.update(users).set({ tokenVersion: 99 }).where(eq(users.id, 1));

    expect(await getLoginNotificationDevices(1, 'new')).toEqual([]);
  });

  test('should say what signed in, and open the devices on a tap', async () => {
    const payload = await buildLoginPayload({
      os: 'iOS 27.2',
      device: 'Apple iPad'
    });

    expect(payload.aps.alert).toEqual({
      title: 'New login detected',
      body: 'iOS 27.2 · Apple iPad signed in to your account on Test Server.'
    });
    expect(payload.kind).toBe('newLogin');
  });

  test('should still alert when the device is unknown', async () => {
    const payload = await buildLoginPayload(undefined);

    expect(payload.aps.alert.body).toBe(
      'A new login was detected on your account on Test Server.'
    );
  });
});
