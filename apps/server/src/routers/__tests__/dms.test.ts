import { ServerEvents } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { getChannelsReadStatesForUser } from '../../db/queries/channels';
import { directMessages, settings } from '../../db/schema';
import { pubsub } from '../../utils/pubsub';

describe('dms router', () => {
  test('should create a direct message channel and allow messaging', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    const { channelId } = await caller1.dms.open({ userId: 2 });

    await caller1.messages.send({
      channelId,
      content: 'hello dm',
      files: []
    });

    const page = await caller2.messages.get({
      channelId,
      cursor: null,
      limit: 50
    });

    expect(page.messages.length).toBe(1);
    expect(page.messages[0]!.content).toBe('hello dm');
  });

  test('should reuse existing direct message channel for same pair', async () => {
    const { caller } = await initTest(1);

    const first = await caller.dms.open({ userId: 2 });
    const second = await caller.dms.open({ userId: 2 });

    expect(second.channelId).toBe(first.channelId);
  });

  test('should list direct message conversations', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    const { channelId } = await caller1.dms.open({ userId: 2 });

    await caller1.messages.send({
      channelId,
      content: 'list dm',
      files: []
    });

    const list1 = await caller1.dms.get();
    const list2 = await caller2.dms.get();

    expect(
      list1.some((dm) => dm.channelId === channelId && dm.userId === 2)
    ).toBe(true);
    expect(
      list2.some((dm) => dm.channelId === channelId && dm.userId === 1)
    ).toBe(true);
  });

  test('should reject creating direct message with self', async () => {
    const { caller } = await initTest(1);

    await expect(caller.dms.open({ userId: 1 })).rejects.toThrow(
      'Cannot create a direct message with yourself'
    );
  });

  test('should reject open and list when direct messages are disabled', async () => {
    const { caller } = await initTest(1);

    await tdb
      .update(settings)
      .set({
        directMessagesEnabled: false
      })
      .execute();

    await expect(caller.dms.open({ userId: 2 })).rejects.toThrow(
      'Direct messages are disabled on this server'
    );

    await expect(caller.dms.get()).rejects.toThrow(
      'Direct messages are disabled on this server'
    );
  });

  test('should return the same channel when the same pair is opened concurrently', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    // both miss the existence read and both insert. the unique index on the pair makes one
    // of them lose, and the loser must be handed the winner's channel rather than a
    // constraint error
    const [first, second] = await Promise.all([
      caller1.dms.open({ userId: 2 }),
      caller2.dms.open({ userId: 1 })
    ]);

    expect(first.channelId).toBe(second.channelId);

    const rows = await tdb
      .select()
      .from(directMessages)
      .where(eq(directMessages.channelId, first.channelId));

    expect(rows.length).toBe(1);
  });

  // the refusal below covers a non participant marking a dm read. the participant doing it is
  // what the badge depends on, and it is the half that broke in R2
  test('should clear the unread count when a participant reads a dm', async () => {
    const dmChannelId = 3;

    const { caller: sender } = await initTest(3);
    const { caller: reader } = await initTest(4);

    // the seed already leaves user 4 one unread message in this conversation
    const seeded = await getChannelsReadStatesForUser(4, dmChannelId);

    expect(seeded[dmChannelId]).toBe(1);

    await sender.messages.send({
      channelId: dmChannelId,
      content: 'unread on purpose'
    });

    const beforeRead = await getChannelsReadStatesForUser(4, dmChannelId);

    expect(beforeRead[dmChannelId]).toBe(2);

    const readStateUpdates: { channelId: number; count: number }[] = [];

    const subscription = pubsub
      .subscribeFor(4, ServerEvents.CHANNEL_READ_STATES_UPDATE)
      .subscribe({
        next: (update) => {
          readStateUpdates.push(update);
        }
      });

    await reader.channels.markAsRead({ channelId: dmChannelId });

    subscription.unsubscribe();

    const afterRead = await getChannelsReadStatesForUser(4, dmChannelId);

    expect(afterRead[dmChannelId]).toBe(0);

    // the reader's other tabs drop the badge off this event, not off a refetch
    expect(readStateUpdates).toEqual([{ channelId: dmChannelId, count: 0 }]);
  });

  test('should keep a dm read once its newest message has been read', async () => {
    const dmChannelId = 3;

    const { caller: sender } = await initTest(3);
    const { caller: reader } = await initTest(4);

    await sender.messages.send({
      channelId: dmChannelId,
      content: 'first'
    });

    await reader.channels.markAsRead({ channelId: dmChannelId });

    // reopening the same conversation must not resurrect the badge
    await reader.channels.markAsRead({ channelId: dmChannelId });

    const afterSecondRead = await getChannelsReadStatesForUser(4, dmChannelId);

    expect(afterSecondRead[dmChannelId]).toBe(0);

    await sender.messages.send({
      channelId: dmChannelId,
      content: 'second'
    });

    const afterNewMessage = await getChannelsReadStatesForUser(4, dmChannelId);

    expect(afterNewMessage[dmChannelId]).toBe(1);
  });

  test('should refuse a non participant every way into a dm, including the owner', async () => {
    // seeded dm between users 3 and 4
    const dmChannelId = 3;

    const { caller: owner } = await initTest(1);
    const { caller: participant } = await initTest(3);

    await expect(
      owner.messages.get({ channelId: dmChannelId })
    ).rejects.toThrow('You are not a participant in this DM channel');

    // send refuses earlier, on the channel permission, so it never reaches the membership
    // check. still a refusal, and the vaguer message leaks less about who is in the dm
    await expect(
      owner.messages.send({ channelId: dmChannelId, content: 'let me in' })
    ).rejects.toThrow('Insufficient channel permissions');

    await expect(
      owner.channels.markAsRead({ channelId: dmChannelId })
    ).rejects.toThrow('You are not a participant in this DM channel');

    // the same reads work for someone who is actually in it, so the refusals above are the
    // membership check and not the routes being broken
    await expect(
      participant.messages.get({ channelId: dmChannelId })
    ).resolves.toBeDefined();
  });
});

describe('direct message privacy', () => {
  test('should allow direct messages until the user turns them off', async () => {
    const { caller } = await initTest(2);

    expect(await caller.users.getPrivacy()).toEqual({
      allowDirectMessages: true
    });

    await caller.users.updatePrivacy({ allowDirectMessages: false });

    expect(await caller.users.getPrivacy()).toEqual({
      allowDirectMessages: false
    });
  });

  test('should refuse a new conversation with someone not accepting them', async () => {
    const { caller: member } = await initTest(2);
    const { caller: owner } = await initTest(1);

    await member.users.updatePrivacy({ allowDirectMessages: false });

    await expect(owner.dms.open({ userId: 2 })).rejects.toThrow(
      "This person isn't accepting direct messages."
    );
  });

  test('should keep an existing conversation open after they are turned off', async () => {
    const { caller: userA } = await initTest(3);
    const { caller: userB } = await initTest(4);

    await userB.users.updatePrivacy({ allowDirectMessages: false });

    // users 3 and 4 share the seeded DM channel 3
    expect(await userA.dms.open({ userId: 4 })).toEqual({ channelId: 3 });
  });

  test('should refuse a privacy setting that is not a boolean', async () => {
    const { caller } = await initTest(2);

    await expect(
      // @ts-expect-error not a boolean
      caller.users.updatePrivacy({ allowDirectMessages: 'no' })
    ).rejects.toThrow();
  });
});

describe('dms.close', () => {
  test('should hide a closed conversation from the closer only', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);
    const { channelId } = await caller1.dms.open({ userId: 2 });

    await caller1.messages.send({ channelId, content: 'before', files: [] });
    await caller1.dms.close({ channelId });

    const closerList = await caller1.dms.get();
    const otherList = await caller2.dms.get();

    expect(closerList.some((dm) => dm.channelId === channelId)).toBe(false);
    expect(otherList.some((dm) => dm.channelId === channelId)).toBe(true);
  });

  test('should bring a closed conversation back with a new message', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);
    const { channelId } = await caller1.dms.open({ userId: 2 });

    await caller1.dms.close({ channelId });
    await Bun.sleep(5);
    await caller2.messages.send({
      channelId,
      content: 'still there?',
      files: []
    });

    const list = await caller1.dms.get();

    expect(list.some((dm) => dm.channelId === channelId)).toBe(true);
  });

  test('should bring a closed conversation back when it is opened again', async () => {
    const { caller } = await initTest(1);
    const { channelId } = await caller.dms.open({ userId: 2 });

    await caller.dms.close({ channelId });
    await caller.dms.open({ userId: 2 });

    const list = await caller.dms.get();

    expect(list.some((dm) => dm.channelId === channelId)).toBe(true);
  });

  test('should refuse someone who is not in the conversation', async () => {
    // seeded dm between users 3 and 4
    const { caller } = await initTest(1);

    await expect(caller.dms.close({ channelId: 3 })).rejects.toThrow(
      'You are not a participant in this DM channel'
    );
  });

  test('should refuse a channel that is not a direct message', async () => {
    const { caller } = await initTest(1);

    await expect(caller.dms.close({ channelId: 1 })).rejects.toThrow(
      'Conversation not found'
    );
  });

  test('should refuse when direct messages are disabled', async () => {
    const { caller } = await initTest(3);

    await tdb.update(settings).set({ directMessagesEnabled: false }).execute();

    await expect(caller.dms.close({ channelId: 3 })).rejects.toThrow(
      'Direct messages are disabled on this server'
    );
  });
});
