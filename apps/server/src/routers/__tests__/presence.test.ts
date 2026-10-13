import { ServerEvents, UserStatus } from '@sharkord/shared';
import { describe, expect, spyOn, test } from 'bun:test';
import { createFakeSocket, initTest } from '../../__tests__/helpers';
import { pubsub } from '../../utils/pubsub';

// a socket of its own makes the user count as connected, a status only shows while they are
const connect = (userId: number) =>
  initTest(userId, { socket: createFakeSocket() });

describe('users presence', () => {
  test('should show the status picked and the custom message to everyone', async () => {
    const { caller } = await connect(2);

    await caller.users.setPresence({
      presence: 'dnd',
      customStatus: 'Raiding, back at 9'
    });

    expect(await caller.users.getPresence()).toEqual({
      presence: 'dnd',
      customStatus: 'Raiding, back at 9'
    });

    const { initialData } = await connect(1);
    const member = initialData.users.find(({ id }) => id === 2);

    expect(member?.status).toBe(UserStatus.DND);
    expect(member?.customStatus).toBe('Raiding, back at 9');
  });

  test('should keep the status picked across joins', async () => {
    const { caller } = await connect(2);

    await caller.users.setPresence({ presence: 'idle', customStatus: null });

    const { initialData } = await connect(2);

    expect(initialData.users.find(({ id }) => id === 2)?.status).toBe(
      UserStatus.IDLE
    );
  });

  test('should show an invisible user as offline to everyone else', async () => {
    const { caller } = await connect(2);

    await caller.users.setPresence({
      presence: 'invisible',
      customStatus: null
    });

    const { initialData } = await connect(1);

    expect(initialData.users.find(({ id }) => id === 2)?.status).toBe(
      UserStatus.OFFLINE
    );
    expect(await caller.users.getPresence()).toEqual({
      presence: 'invisible',
      customStatus: null
    });
  });

  test('should show offline for someone not connected, whatever they picked', async () => {
    const { caller } = await initTest(2);

    await caller.users.setPresence({ presence: 'dnd', customStatus: null });

    const { initialData } = await connect(1);

    expect(initialData.users.find(({ id }) => id === 2)?.status).toBe(
      UserStatus.OFFLINE
    );
  });

  test('should publish the new status as a user update', async () => {
    const { caller } = await connect(2);
    const publish = spyOn(pubsub, 'publish');

    await caller.users.setPresence({ presence: 'dnd', customStatus: 'busy' });

    const update = publish.mock.calls.find(
      ([event]) => event === ServerEvents.USER_UPDATE
    );

    expect(update?.[1]).toMatchObject({
      id: 2,
      status: UserStatus.DND,
      customStatus: 'busy'
    });
  });

  test('should clear the custom message when it is empty', async () => {
    const { caller } = await connect(2);

    await caller.users.setPresence({
      presence: 'online',
      customStatus: 'temporary'
    });
    await caller.users.setPresence({ presence: 'online', customStatus: '   ' });

    expect((await caller.users.getPresence()).customStatus).toBeNull();
  });

  test('should refuse an unknown status or a message that is too long', async () => {
    const { caller } = await connect(2);

    await expect(
      // @ts-expect-error not one of the statuses
      caller.users.setPresence({ presence: 'away', customStatus: null })
    ).rejects.toThrow();
    await expect(
      caller.users.setPresence({
        presence: 'online',
        customStatus: 'x'.repeat(129)
      })
    ).rejects.toThrow();
  });
});
