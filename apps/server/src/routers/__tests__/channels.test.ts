import { ChannelPermission, ChannelType, ServerEvents } from '@sharkord/shared';
import { describe, expect, spyOn, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import {
  createFakeSocket,
  initTest,
  sendMessage
} from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { getChannelsReadStatesForUser } from '../../db/queries/channels';
import { messages } from '../../db/schema';
import { VoiceRuntime } from '../../runtimes/voice';
import { pubsub } from '../../utils/pubsub';

describe('channels router', () => {
  test('should throw when user lacks permissions (add)', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.channels.add({
        type: ChannelType.TEXT,
        name: 'new-channel',
        categoryId: 1
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should throw when user lacks permissions (get)', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.channels.get({
        channelId: 1
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should throw when user lacks permissions (update)', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.channels.update({
        channelId: 1,
        name: 'updated-channel',
        topic: 'Updated topic',
        private: false
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should throw when user lacks permissions (delete)', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.channels.delete({
        channelId: 1
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should throw when user lacks permissions (reorder)', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.channels.reorder({
        categoryId: 1,
        channelIds: [2, 1]
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should throw when user lacks permissions (updatePermissions)', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.channels.updatePermissions({
        channelId: 1,
        roleId: 1,
        permissions: [ChannelPermission.VIEW_CHANNEL]
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should throw when user lacks permissions (getPermissions)', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.channels.getPermissions({
        channelId: 1
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should throw when user lacks permissions (deletePermissions)', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.channels.deletePermissions({
        channelId: 1,
        roleId: 1
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should create a new text channel', async () => {
    const { caller } = await initTest();

    const channelId = await caller.channels.add({
      type: ChannelType.TEXT,
      name: 'test-channel',
      categoryId: 1
    });

    const channel = await caller.channels.get({ channelId });

    expect(channel).toBeDefined();
    expect(channel.name).toBe('test-channel');
    expect(channel.type).toBe(ChannelType.TEXT);
    expect(channel.categoryId).toBe(1);
  });

  test('should create a new voice channel', async () => {
    const { caller } = await initTest();

    const channelId = await caller.channels.add({
      type: ChannelType.VOICE,
      name: 'voice-lounge',
      categoryId: 1
    });

    const channel = await caller.channels.get({ channelId });

    expect(channel).toBeDefined();
    expect(channel.name).toBe('voice-lounge');
    expect(channel.type).toBe(ChannelType.VOICE);
  });

  test('should get existing channel', async () => {
    const { caller } = await initTest();

    const channel = await caller.channels.get({
      channelId: 1
    });

    expect(channel).toBeDefined();
    expect(channel.id).toBe(1);
    expect(channel.name).toBeDefined();
  });

  test('should update channel name, topic, and private status', async () => {
    const { caller } = await initTest();

    await caller.channels.update({
      channelId: 1,
      name: 'updated-channel',
      topic: 'This is a test topic',
      private: true
    });

    const channel = await caller.channels.get({
      channelId: 1
    });

    expect(channel.name).toBe('updated-channel');
    expect(channel.topic).toBe('This is a test topic');
    expect(channel.private).toBe(true);
  });

  test('should throw when adding a channel to a non-existing category', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.add({
        type: ChannelType.TEXT,
        name: 'orphan-channel',
        categoryId: 9999
      })
    ).rejects.toThrow('Category not found');
  });

  test('should throw when updating permissions for a non-existing role', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.updatePermissions({
        channelId: 1,
        roleId: 9999,
        permissions: []
      })
    ).rejects.toThrow('Role not found');
  });

  test('should throw when updating a non-existing channel', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.update({
        channelId: 9999,
        name: 'ghost-channel'
      })
    ).rejects.toThrow('Channel not found');
  });

  test('should throw when updating a channel with no values', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.update({
        channelId: 1
      })
    ).rejects.toThrow('Nothing to update');
  });

  test('should update channel topic to null', async () => {
    const { caller } = await initTest();

    await caller.channels.update({
      channelId: 1,
      name: 'test-channel',
      topic: null,
      private: false
    });

    const channel = await caller.channels.get({
      channelId: 1
    });

    expect(channel.topic).toBeNull();
  });

  test('should delete existing channel', async () => {
    const { caller } = await initTest();

    const newChannelId = await caller.channels.add({
      type: ChannelType.TEXT,
      name: 'temp-channel',
      categoryId: 1
    });

    await caller.channels.delete({
      channelId: newChannelId
    });

    await expect(
      caller.channels.get({
        channelId: newChannelId
      })
    ).rejects.toThrow('Channel not found');
  });

  // the client cannot clear a call it was never told ended: this is the event R4's fix hangs
  // off, so a delete that quietly leaves the runtime standing puts the bug straight back
  test('should end the call in a voice channel that is deleted', async () => {
    const { caller } = await initTest();

    const runtime = new VoiceRuntime(2);

    runtime.addUser(2, { micMuted: false, soundMuted: false });

    const departures: { channelId: number; userId: number }[] = [];

    const subscription = pubsub
      .subscribeFor(2, ServerEvents.USER_LEAVE_VOICE)
      .subscribe({
        next: (departure) => {
          departures.push(departure);
        }
      });

    await caller.channels.delete({ channelId: 2 });

    subscription.unsubscribe();

    expect(VoiceRuntime.findById(2)).toBeUndefined();
    expect(departures).toEqual([{ channelId: 2, userId: 2 }]);
  });

  // channel 5 is private, the default role may view it and user 2 is denied. the client can
  // only drop a channel it is told about, and the audience is read after the write, so the
  // person who just lost access is the one at risk of never hearing
  describe('channel access events', () => {
    const RESTRICTED_CHANNEL_ID = 5;

    const collectFor = (userId: number) => {
      const created: number[] = [];
      const deleted: number[] = [];

      const subscriptions = [
        pubsub.subscribeFor(userId, ServerEvents.CHANNEL_CREATE).subscribe({
          next: (channel) => {
            created.push(channel.id);
          }
        }),
        pubsub.subscribeFor(userId, ServerEvents.CHANNEL_DELETE).subscribe({
          next: (channelId) => {
            deleted.push(channelId);
          }
        })
      ];

      return {
        created,
        deleted,
        stop: () => subscriptions.forEach((s) => s.unsubscribe())
      };
    };

    test('should tell a user who just lost access that the channel is gone', async () => {
      const { caller } = await initTest();

      // the audience is online users only, so the watcher has to hold a socket to be in it
      await initTest(3, { socket: createFakeSocket() });

      // user 3 can see it through the default role, so they are in the audience beforehand
      const events = collectFor(3);

      try {
        await caller.channels.updatePermissions({
          channelId: RESTRICTED_CHANNEL_ID,
          userId: 3,
          permissions: []
        });

        expect(events.deleted).toEqual([RESTRICTED_CHANNEL_ID]);
        expect(events.created).toEqual([]);
      } finally {
        events.stop();
      }
    });

    test('should send the channel to a user who just gained access', async () => {
      const { caller } = await initTest();

      await initTest(2, { socket: createFakeSocket() });

      // user 2 is denied, so their client has never been sent this channel
      const events = collectFor(2);

      try {
        await caller.channels.updatePermissions({
          channelId: RESTRICTED_CHANNEL_ID,
          userId: 2,
          permissions: [ChannelPermission.VIEW_CHANNEL]
        });

        expect(events.created).toEqual([RESTRICTED_CHANNEL_ID]);
        expect(events.deleted).toEqual([]);
      } finally {
        events.stop();
      }
    });
  });

  test('should throw when deleting non-existing channel', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.delete({
        channelId: 999
      })
    ).rejects.toThrow('Channel not found');
  });

  test('should throw when getting non-existing channel', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.get({
        channelId: 999
      })
    ).rejects.toThrow('Channel not found');
  });

  test('should reorder channels in a category', async () => {
    const { caller } = await initTest();

    const channelAId = await caller.channels.add({
      type: ChannelType.TEXT,
      name: 'channel-a',
      categoryId: 1
    });

    const channelBId = await caller.channels.add({
      type: ChannelType.TEXT,
      name: 'channel-b',
      categoryId: 1
    });

    await caller.channels.reorder({
      categoryId: 1,
      channelIds: [channelAId, 1, channelBId]
    });

    const [channel1, channel2, channelA, channelB] = await Promise.all([
      caller.channels.get({ channelId: 1 }),
      caller.channels.get({ channelId: 2 }),
      caller.channels.get({ channelId: channelAId }),
      caller.channels.get({ channelId: channelBId })
    ]);

    expect(channelA.position).toBe(1);
    expect(channel1.position).toBe(2);
    expect(channelB.position).toBe(3);
    expect(channel2.position).toBe(1);
  });

  test('should reorder channels when some ids are missing from payload', async () => {
    const { caller } = await initTest();

    const channelAId = await caller.channels.add({
      type: ChannelType.TEXT,
      name: 'channel-a',
      categoryId: 1
    });

    const channelBId = await caller.channels.add({
      type: ChannelType.TEXT,
      name: 'channel-b',
      categoryId: 1
    });

    await caller.channels.reorder({
      categoryId: 1,
      channelIds: [channelBId, 1]
    });

    const [channel1, channel2, channelA, channelB] = await Promise.all([
      caller.channels.get({ channelId: 1 }),
      caller.channels.get({ channelId: 2 }),
      caller.channels.get({ channelId: channelAId }),
      caller.channels.get({ channelId: channelBId })
    ]);

    expect(channelB.position).toBe(1);
    expect(channel1.position).toBe(2);
    expect(channelA.position).toBe(3);
    expect(channel2.position).toBe(1);
  });

  test('should move a channel into another category at the requested index', async () => {
    const { caller } = await initTest();

    await caller.channels.reorder({
      categoryId: 1,
      channelIds: [2, 1]
    });

    const [channel1, channel2, channel4] = await Promise.all([
      caller.channels.get({ channelId: 1 }),
      caller.channels.get({ channelId: 2 }),
      caller.channels.get({ channelId: 4 })
    ]);

    expect(channel2.categoryId).toBe(1);
    expect(channel2.position).toBe(1);
    expect(channel1.categoryId).toBe(1);
    expect(channel1.position).toBe(2);

    // the source category is untouched, it only ends up with a gap in positions
    expect(channel4.categoryId).toBe(2);
    expect(channel4.position).toBe(2);
  });

  test('should throw when moving a DM channel into a category', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.reorder({
        categoryId: 1,
        channelIds: [3, 1]
      })
    ).rejects.toThrow('Cannot move DM channels into a category');
  });

  test('should throw when reordering into a category that does not exist', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.reorder({
        categoryId: 999,
        channelIds: [1]
      })
    ).rejects.toThrow('Category not found');
  });

  test('should set channel permissions for a role', async () => {
    const { caller } = await initTest();

    await caller.channels.updatePermissions({
      channelId: 1,
      roleId: 1,
      permissions: [
        ChannelPermission.VIEW_CHANNEL,
        ChannelPermission.SEND_MESSAGES
      ]
    });

    const permissions = await caller.channels.getPermissions({
      channelId: 1
    });

    expect(permissions).toBeDefined();
    expect(permissions.rolePermissions).toBeDefined();
    expect(permissions.rolePermissions.length).toBeGreaterThan(0);

    const rolePerms = permissions.rolePermissions.filter((p) => p.roleId === 1);

    expect(rolePerms.length).toBeGreaterThan(0);

    const viewChannelPerm = rolePerms.find(
      (p) => p.permission === ChannelPermission.VIEW_CHANNEL
    );
    const sendMessagesPerm = rolePerms.find(
      (p) => p.permission === ChannelPermission.SEND_MESSAGES
    );

    expect(viewChannelPerm?.allow).toBe(true);
    expect(sendMessagesPerm?.allow).toBe(true);
  });

  test('should set channel permissions for a user', async () => {
    const { caller } = await initTest();

    await caller.channels.updatePermissions({
      channelId: 1,
      userId: 1,
      permissions: [ChannelPermission.VIEW_CHANNEL]
    });

    const permissions = await caller.channels.getPermissions({
      channelId: 1
    });

    expect(permissions.userPermissions).toBeDefined();
    expect(permissions.userPermissions.length).toBeGreaterThan(0);

    const userPerms = permissions.userPermissions.filter((p) => p.userId === 1);

    expect(userPerms.length).toBeGreaterThan(0);

    const viewChannelPerm = userPerms.find(
      (p) => p.permission === ChannelPermission.VIEW_CHANNEL
    );

    expect(viewChannelPerm?.allow).toBe(true);
  });

  test('should create empty permission set with isCreate flag', async () => {
    const { caller } = await initTest();

    await caller.channels.updatePermissions({
      channelId: 1,
      roleId: 2,
      isCreate: true,
      permissions: [ChannelPermission.VIEW_CHANNEL] // should be ignored
    });

    const permissions = await caller.channels.getPermissions({
      channelId: 1
    });

    const rolePerms = permissions.rolePermissions.filter((p) => p.roleId === 2);
    const allowedPerms = rolePerms.filter((p) => p.allow);

    expect(allowedPerms.length).toBe(0);
  });

  test('should delete channel permissions for a role', async () => {
    const { caller } = await initTest();

    await caller.channels.updatePermissions({
      channelId: 1,
      roleId: 1,
      permissions: [ChannelPermission.VIEW_CHANNEL]
    });

    let permissions = await caller.channels.getPermissions({
      channelId: 1
    });

    const rolePermsBeforeDelete = permissions.rolePermissions.filter(
      (p) => p.roleId === 1
    );

    expect(rolePermsBeforeDelete.length).toBeGreaterThan(0);

    await caller.channels.deletePermissions({
      channelId: 1,
      roleId: 1
    });

    permissions = await caller.channels.getPermissions({
      channelId: 1
    });

    const rolePermsAfterDelete = permissions.rolePermissions.filter(
      (p) => p.roleId === 1
    );

    expect(rolePermsAfterDelete.length).toBe(0);
  });

  test('should delete channel permissions for a user', async () => {
    const { caller } = await initTest();

    await caller.channels.updatePermissions({
      channelId: 1,
      userId: 1,
      permissions: [ChannelPermission.VIEW_CHANNEL]
    });

    let permissions = await caller.channels.getPermissions({
      channelId: 1
    });

    const userPermsBeforeDelete = permissions.userPermissions.filter(
      (p) => p.userId === 1
    );

    expect(userPermsBeforeDelete.length).toBeGreaterThan(0);

    await caller.channels.deletePermissions({
      channelId: 1,
      userId: 1
    });

    permissions = await caller.channels.getPermissions({
      channelId: 1
    });

    const userPermsAfterDelete = permissions.userPermissions.filter(
      (p) => p.userId === 1
    );

    expect(userPermsAfterDelete.length).toBe(0);
  });

  test('should mark channel as read', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    const beforeMsgSendReadStates = await getChannelsReadStatesForUser(2, 2);

    // before sending any messages, there should be no read state
    expect(beforeMsgSendReadStates[2]).toBeUndefined();

    await caller1.messages.send({
      channelId: 2,
      content: 'Test message for read state',
      files: []
    });

    const beforeReadStates = await getChannelsReadStatesForUser(2, 2);

    // message has been sent, there should be 1 unread message
    expect(beforeReadStates[2]).toBeDefined();
    expect(beforeReadStates[2]).toBe(1);

    await caller2.channels.markAsRead({
      channelId: 2
    });

    const afterReadStates = await getChannelsReadStatesForUser(2, 2);

    // after marking as read, there should be 0 unread messages
    expect(afterReadStates[2]).toBeDefined();
    expect(afterReadStates[2]).toBe(0);
  });

  // the unread count compares ids, so the marker has to be the highest id in the channel.
  // picking the newest timestamp instead leaves anything stamped earlier but inserted later
  // unread forever, and marking as read again keeps choosing the same wrong row. a clock
  // that steps backwards between two messages is enough to produce it
  test('should mark as read up to the highest message id, not the newest timestamp', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    await caller1.messages.send({
      channelId: 2,
      content: 'Sent first, stamped later',
      files: []
    });

    const realNow = Date.now;

    Date.now = () => realNow() - 60_000;

    try {
      await caller1.messages.send({
        channelId: 2,
        content: 'Sent second, stamped earlier',
        files: []
      });
    } finally {
      Date.now = realNow;
    }

    const beforeReadStates = await getChannelsReadStatesForUser(2, 2);

    expect(beforeReadStates[2]).toBe(2);

    await caller2.channels.markAsRead({ channelId: 2 });

    const afterReadStates = await getChannelsReadStatesForUser(2, 2);

    expect(afterReadStates[2]).toBe(0);
  });

  test('should not mark a channel as read just by fetching its messages', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    await caller1.messages.send({
      channelId: 2,
      content: 'Unread for user two',
      files: []
    });

    // reading a page used to upsert the read state to the newest message, so
    // scrolling back through history silently marked everything read
    await caller2.messages.get({ channelId: 2, cursor: null, limit: 50 });

    const readStates = await getChannelsReadStatesForUser(2, 2);

    expect(readStates[2]).toBe(1);
  });

  test('should mark channel as read twice without conflicting', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    await caller1.messages.send({
      channelId: 2,
      content: 'Test message',
      files: []
    });

    await Promise.all([
      caller2.channels.markAsRead({ channelId: 2 }),
      caller2.channels.markAsRead({ channelId: 2 })
    ]);

    const readStates = await getChannelsReadStatesForUser(2, 2);

    expect(readStates[2]).toBe(0);
  });

  test('should publish a read state update when marking as read', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    await caller1.messages.send({
      channelId: 2,
      content: 'Test message',
      files: []
    });

    const events: { channelId: number; count: number }[] = [];

    const subscription = pubsub
      .subscribeFor(2, ServerEvents.CHANNEL_READ_STATES_UPDATE)
      .subscribe({
        next: (event) => {
          events.push(event);
        }
      });

    await caller2.channels.markAsRead({ channelId: 2 });

    subscription.unsubscribe();

    expect(events).toEqual([{ channelId: 2, count: 0 }]);
  });

  test('should mark channel as read with no messages', async () => {
    const { caller } = await initTest();

    // channel 2 has no messages, so marking as read should do nothing
    await caller.channels.markAsRead({
      channelId: 2
    });

    const readStates = await getChannelsReadStatesForUser(1, 2);

    // should not create a read state for empty channel
    expect(readStates[2]).toBeUndefined();
  });

  test('should update existing read state when marking as read again', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    // user 1 sends first message
    await caller1.messages.send({
      channelId: 2,
      content: 'First message',
      files: []
    });

    // user 2 marks as read
    await caller2.channels.markAsRead({
      channelId: 2
    });

    const firstReadStates = await getChannelsReadStatesForUser(2, 2);

    expect(firstReadStates[2]).toBe(0);

    // user 1 sends another message
    await caller1.messages.send({
      channelId: 2,
      content: 'Second message',
      files: []
    });

    const beforeSecondMark = await getChannelsReadStatesForUser(2, 2);

    expect(beforeSecondMark[2]).toBe(1);

    // user 2 marks as read again
    await caller2.channels.markAsRead({
      channelId: 2
    });

    const afterSecondMark = await getChannelsReadStatesForUser(2, 2);

    expect(afterSecondMark[2]).toBe(0);
  });

  test('should track unread count correctly with multiple messages', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    // user 1 sends 3 messages
    await caller1.messages.send({
      channelId: 2,
      content: 'Message 1',
      files: []
    });

    await caller1.messages.send({
      channelId: 2,
      content: 'Message 2',
      files: []
    });

    await caller1.messages.send({
      channelId: 2,
      content: 'Message 3',
      files: []
    });

    const readStates = await getChannelsReadStatesForUser(2, 2);

    // user 2 should have 3 unread messages
    expect(readStates[2]).toBe(3);

    // user 2 marks as read
    await caller2.channels.markAsRead({
      channelId: 2
    });

    const afterMark = await getChannelsReadStatesForUser(2, 2);

    expect(afterMark[2]).toBe(0);
  });

  test('should not count own messages as unread', async () => {
    const { caller } = await initTest();

    // user sends messages to channel
    await caller.messages.send({
      channelId: 2,
      content: 'My message 1',
      files: []
    });

    await caller.messages.send({
      channelId: 2,
      content: 'My message 2',
      files: []
    });

    const readStates = await getChannelsReadStatesForUser(1, 2);

    // should have 0 unread messages since user sent them themselves
    expect(readStates[2]).toBe(0);
  });

  test('should not count thread replies as unread in channel', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    // user 1 sends a root message
    const parentId = await sendMessage(caller1, {
      channelId: 2,
      content: 'Root message',
      files: []
    });

    // user 2 marks as read so baseline is 0
    await caller2.channels.markAsRead({ channelId: 2 });

    const afterMarkRead = await getChannelsReadStatesForUser(2, 2);

    expect(afterMarkRead[2]).toBe(0);

    // user 1 sends thread replies
    await caller1.messages.send({
      channelId: 2,
      content: 'Thread reply 1',
      files: [],
      parentMessageId: parentId
    });

    await caller1.messages.send({
      channelId: 2,
      content: 'Thread reply 2',
      files: [],
      parentMessageId: parentId
    });

    const afterReplies = await getChannelsReadStatesForUser(2, 2);

    // thread replies should NOT increment the unread count
    expect(afterReplies[2]).toBe(0);
  });

  test('should only count root messages as unread when mixed with thread replies', async () => {
    const { caller: caller1 } = await initTest(1);

    // user 1 sends a root message
    const parentId = await sendMessage(caller1, {
      channelId: 2,
      content: 'Root 1',
      files: []
    });

    // user 1 sends thread replies
    await caller1.messages.send({
      channelId: 2,
      content: 'Reply to root 1',
      files: [],
      parentMessageId: parentId
    });

    // user 1 sends another root message
    await caller1.messages.send({
      channelId: 2,
      content: 'Root 2',
      files: []
    });

    const readStates = await getChannelsReadStatesForUser(2, 2);

    // should be 2 (two root messages), NOT 3 (which would include the thread reply)
    expect(readStates[2]).toBe(2);
  });

  test('should mark as read correctly when thread replies exist', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    const parentId = await sendMessage(caller1, {
      channelId: 2,
      content: 'Root message',
      files: []
    });

    await caller1.messages.send({
      channelId: 2,
      content: 'Thread reply',
      files: [],
      parentMessageId: parentId
    });

    await caller1.messages.send({
      channelId: 2,
      content: 'Another root',
      files: []
    });

    const beforeMark = await getChannelsReadStatesForUser(2, 2);

    // 2 root messages unread
    expect(beforeMark[2]).toBe(2);

    await caller2.channels.markAsRead({ channelId: 2 });

    const afterMark = await getChannelsReadStatesForUser(2, 2);

    expect(afterMark[2]).toBe(0);
  });

  test('should not include DM channels between other users in read states', async () => {
    // the seed creates a DM channel (id 3) between User A (3) and User B (4)
    // with a message from User A. User 1 and User 2 should NOT see this in their read states.

    const readStatesUser1 = await getChannelsReadStatesForUser(1);
    const readStatesUser2 = await getChannelsReadStatesForUser(2);

    // channel 3 is the DM between User A and User B - should not appear for User 1 or User 2
    expect(readStatesUser1[3]).toBeUndefined();
    expect(readStatesUser2[3]).toBeUndefined();
  });

  test('should include DM channels the user participates in for read states', async () => {
    // User B (4) is a participant in the DM channel (3) with User A (3)
    // User A sent a message, so User B should see 1 unread
    const readStatesUserB = await getChannelsReadStatesForUser(4);

    expect(readStatesUserB[3]).toBe(1);
  });

  test('should not count own messages as unread in DM channels', async () => {
    // User A (3) sent the message in the DM channel (3), so they should see 0 unread
    const readStatesUserA = await getChannelsReadStatesForUser(3);

    expect(readStatesUserA[3]).toBe(0);
  });

  test('should still include regular channels in read states when DM channels exist', async () => {
    // the seed has a message in channel 1 (General) from User 1 (Test Owner)
    // User 2 should see 1 unread in channel 1
    const readStatesUser2 = await getChannelsReadStatesForUser(2);

    expect(readStatesUser2[1]).toBe(1);
  });

  test('should track unread counts correctly across multiple channels', async () => {
    const { caller: caller1 } = await initTest(1);
    const { caller: caller2 } = await initTest(2);

    // user 1 sends messages in channel 1 and channel 2
    await caller1.messages.send({
      channelId: 1,
      content: 'Message in channel 1',
      files: []
    });

    await caller1.messages.send({
      channelId: 2,
      content: 'Message in channel 2',
      files: []
    });

    const readStatesUser2 = await getChannelsReadStatesForUser(2);

    expect(readStatesUser2[1]).toBe(2); // 1 message from mocks + 1 new message
    expect(readStatesUser2[2]).toBe(1);

    // user 2 marks channel 1 as read
    await caller2.channels.markAsRead({ channelId: 1 });

    const afterMarkUser2 = await getChannelsReadStatesForUser(2);

    expect(afterMarkUser2[1]).toBe(0);
    expect(afterMarkUser2[2]).toBe(1);
  });

  test('should validate channel name length (too short)', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.add({
        type: ChannelType.TEXT,
        name: '',
        categoryId: 1
      })
    ).rejects.toThrow();
  });

  test('should validate channel name length (too long)', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.add({
        type: ChannelType.TEXT,
        name: 'this-is-a-very-long-channel-name-that-exceeds-the-limit',
        categoryId: 1
      })
    ).rejects.toThrow();
  });

  test('should validate topic length (too long)', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.update({
        channelId: 1,
        name: 'test-channel',
        topic: 'a'.repeat(200),
        private: false
      })
    ).rejects.toThrow();
  });

  test('should create channel with incrementing position', async () => {
    const { caller } = await initTest();

    const firstChannelId = await caller.channels.add({
      type: ChannelType.TEXT,
      name: 'first-channel',
      categoryId: 1
    });

    const firstChannel = await caller.channels.get({
      channelId: firstChannelId
    });

    const secondChannelId = await caller.channels.add({
      type: ChannelType.TEXT,
      name: 'second-channel',
      categoryId: 1
    });

    const secondChannel = await caller.channels.get({
      channelId: secondChannelId
    });

    expect(secondChannel.position).toBeGreaterThan(firstChannel.position);
  });

  test('should allow multiple permission types on same channel', async () => {
    const { caller } = await initTest();

    await caller.channels.updatePermissions({
      channelId: 1,
      roleId: 1,
      permissions: [ChannelPermission.VIEW_CHANNEL]
    });

    await caller.channels.updatePermissions({
      channelId: 1,
      userId: 1,
      permissions: [ChannelPermission.SEND_MESSAGES]
    });

    const permissions = await caller.channels.getPermissions({
      channelId: 1
    });

    expect(permissions.rolePermissions.length).toBeGreaterThan(0);
    expect(permissions.userPermissions.length).toBeGreaterThan(0);
  });

  test('should update existing permissions when called again', async () => {
    const { caller } = await initTest();

    await caller.channels.updatePermissions({
      channelId: 1,
      roleId: 1,
      permissions: [ChannelPermission.VIEW_CHANNEL]
    });

    await caller.channels.updatePermissions({
      channelId: 1,
      roleId: 1,
      permissions: [
        ChannelPermission.VIEW_CHANNEL,
        ChannelPermission.SEND_MESSAGES
      ]
    });

    const permissions = await caller.channels.getPermissions({
      channelId: 1
    });

    const rolePerms = permissions.rolePermissions.filter((p) => p.roleId === 1);

    const sendMessagesPerm = rolePerms.find(
      (p) => p.permission === ChannelPermission.SEND_MESSAGES
    );

    expect(sendMessagesPerm?.allow).toBe(true);
  });

  test('should create channels in different categories', async () => {
    const { caller } = await initTest();

    const catOneChannelId = await caller.channels.add({
      type: ChannelType.TEXT,
      name: 'cat-1-channel',
      categoryId: 1
    });

    const catTwoChannelId = await caller.channels.add({
      type: ChannelType.TEXT,
      name: 'cat-2-channel',
      categoryId: 2
    });

    const channel1 = await caller.channels.get({ channelId: catOneChannelId });
    const channel2 = await caller.channels.get({ channelId: catTwoChannelId });

    expect(channel1.categoryId).toBe(1);
    expect(channel2.categoryId).toBe(2);
  });

  test('should throw when deleting a DM channel', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.delete({
        channelId: 3
      })
    ).rejects.toThrow('Cannot delete DM channels');
  });

  test('should throw when updating a DM channel', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.update({
        channelId: 3,
        name: 'new-name',
        topic: 'new-topic',
        private: false
      })
    ).rejects.toThrow('Cannot update DM channels');
  });

  test('should mark DM channel as read', async () => {
    // seed: DM channel 3 between User A (3) and User B (4), with 1 message from User A
    const { caller: callerB } = await initTest(4);

    const beforeRead = await getChannelsReadStatesForUser(4);

    expect(beforeRead[3]).toBe(1);

    await callerB.channels.markAsRead({ channelId: 3 });

    const afterRead = await getChannelsReadStatesForUser(4);

    expect(afterRead[3]).toBe(0);
  });

  test('should track unread count correctly with multiple DM messages', async () => {
    // seed already has 1 message from User A in DM channel 3
    const { caller: callerA } = await initTest(3);

    await callerA.messages.send({
      channelId: 3,
      content: 'DM message 2',
      files: []
    });

    await callerA.messages.send({
      channelId: 3,
      content: 'DM message 3',
      files: []
    });

    const readStatesB = await getChannelsReadStatesForUser(4);

    // 1 from seed + 2 new = 3 unread for User B
    expect(readStatesB[3]).toBe(3);
  });

  test('should update existing DM read state when marking as read again', async () => {
    const { caller: callerA } = await initTest(3);
    const { caller: callerB } = await initTest(4);

    // User B marks as read (clears the seed message)
    await callerB.channels.markAsRead({ channelId: 3 });

    const afterFirstMark = await getChannelsReadStatesForUser(4);

    expect(afterFirstMark[3]).toBe(0);

    // User A sends another message
    await callerA.messages.send({
      channelId: 3,
      content: 'New DM after mark',
      files: []
    });

    const beforeSecondMark = await getChannelsReadStatesForUser(4);

    expect(beforeSecondMark[3]).toBe(1);

    // User B marks as read again
    await callerB.channels.markAsRead({ channelId: 3 });

    const afterSecondMark = await getChannelsReadStatesForUser(4);

    expect(afterSecondMark[3]).toBe(0);
  });

  test('should not count own messages as unread in DM (interactive)', async () => {
    const { caller: callerA } = await initTest(3);

    // User A sends more messages in the DM
    await callerA.messages.send({
      channelId: 3,
      content: 'Another message from A',
      files: []
    });

    const readStatesA = await getChannelsReadStatesForUser(3);

    // User A sent all messages, so they should have 0 unread
    expect(readStatesA[3]).toBe(0);
  });

  test('should throw when non-participant tries to mark DM channel as read', async () => {
    // User 1 is not a participant in DM channel 3 (between User A and User B)
    const { caller } = await initTest(1);

    await expect(caller.channels.markAsRead({ channelId: 3 })).rejects.toThrow(
      'You are not a participant in this DM channel'
    );
  });

  test('should throw when updating permissions for a DM channel', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.updatePermissions({
        channelId: 3,
        roleId: 1,
        permissions: [ChannelPermission.VIEW_CHANNEL]
      })
    ).rejects.toThrow('Cannot update DM channel permissions');
  });

  test('should throw when deleting permissions for a DM channel', async () => {
    const { caller } = await initTest();

    await expect(
      caller.channels.deletePermissions({
        channelId: 3,
        roleId: 1
      })
    ).rejects.toThrow('Cannot delete DM channel permissions');
  });

  describe('channel permission management scope', () => {
    // user 5 holds MANAGE_CHANNEL_PERMISSIONS but has no access to the private channels
    const MODERATOR_ID = 5;
    const PRIVATE_VOICE_ID = 4;
    const RESTRICTED_CHANNEL_ID = 5;

    test('should not read permissions of a channel the caller cannot see', async () => {
      const { caller } = await initTest(MODERATOR_ID);

      await expect(
        caller.channels.getPermissions({ channelId: PRIVATE_VOICE_ID })
      ).rejects.toThrow('Insufficient channel permissions');
    });

    test('should not let a caller grant themselves a channel they cannot see', async () => {
      const { caller } = await initTest(MODERATOR_ID);

      await expect(
        caller.channels.updatePermissions({
          channelId: PRIVATE_VOICE_ID,
          userId: MODERATOR_ID,
          permissions: [ChannelPermission.VIEW_CHANNEL]
        })
      ).rejects.toThrow('Insufficient channel permissions');

      const { caller: owner } = await initTest();
      const { userPermissions } = await owner.channels.getPermissions({
        channelId: PRIVATE_VOICE_ID
      });

      expect(userPermissions).toHaveLength(0);
    });

    test('should not delete permissions on a channel the caller cannot see', async () => {
      const { caller } = await initTest(MODERATOR_ID);

      await expect(
        caller.channels.deletePermissions({
          channelId: RESTRICTED_CHANNEL_ID,
          userId: 2
        })
      ).rejects.toThrow('Insufficient channel permissions');

      const { caller: owner } = await initTest();
      const { userPermissions } = await owner.channels.getPermissions({
        channelId: RESTRICTED_CHANNEL_ID
      });

      expect(userPermissions.some((row) => row.userId === 2)).toBe(true);
    });

    test('should throw when reading permissions of a missing channel', async () => {
      const { caller } = await initTest();

      await expect(
        caller.channels.getPermissions({ channelId: 999 })
      ).rejects.toThrow('Channel not found');
    });

    test('should throw when deleting permissions of a missing channel', async () => {
      const { caller } = await initTest();

      await expect(
        caller.channels.deletePermissions({ channelId: 999, userId: 2 })
      ).rejects.toThrow('Channel not found');
    });

    // channel 5's default role row is widened here, and user 2's own row denies on top of it,
    // so clearing that row is what would hand user 2 the role's permissions
    const setUpRestrictedChannel = async (
      memberRowAllows: ChannelPermission[]
    ) => {
      const { caller: owner } = await initTest();

      await owner.channels.updatePermissions({
        channelId: RESTRICTED_CHANNEL_ID,
        roleId: 2,
        permissions: [
          ChannelPermission.VIEW_CHANNEL,
          ChannelPermission.SEND_MESSAGES
        ]
      });
      await owner.channels.updatePermissions({
        channelId: RESTRICTED_CHANNEL_ID,
        userId: 2,
        permissions: memberRowAllows
      });
      await owner.channels.updatePermissions({
        channelId: RESTRICTED_CHANNEL_ID,
        userId: MODERATOR_ID,
        permissions: [ChannelPermission.VIEW_CHANNEL]
      });

      return owner;
    };

    test('should not clear a row whose removal grants a permission the caller lacks', async () => {
      const owner = await setUpRestrictedChannel([]);
      const { caller } = await initTest(MODERATOR_ID);

      await expect(
        caller.channels.deletePermissions({
          channelId: RESTRICTED_CHANNEL_ID,
          userId: 2
        })
      ).rejects.toThrow(
        'You cannot grant channel permissions that you do not have.'
      );

      const { userPermissions } = await owner.channels.getPermissions({
        channelId: RESTRICTED_CHANNEL_ID
      });

      expect(userPermissions.some((row) => row.userId === 2)).toBe(true);
    });

    test('should clear a row whose removal only grants what the caller holds', async () => {
      const owner = await setUpRestrictedChannel([
        ChannelPermission.SEND_MESSAGES
      ]);
      const { caller } = await initTest(MODERATOR_ID);

      await caller.channels.deletePermissions({
        channelId: RESTRICTED_CHANNEL_ID,
        userId: 2
      });

      const { userPermissions } = await owner.channels.getPermissions({
        channelId: RESTRICTED_CHANNEL_ID
      });

      expect(userPermissions.some((row) => row.userId === 2)).toBe(false);
    });

    test('should only let a caller grant channel permissions they hold', async () => {
      const { caller: owner } = await initTest();

      await owner.channels.updatePermissions({
        channelId: PRIVATE_VOICE_ID,
        userId: MODERATOR_ID,
        permissions: [ChannelPermission.VIEW_CHANNEL]
      });

      const { caller } = await initTest(MODERATOR_ID);

      await expect(
        caller.channels.updatePermissions({
          channelId: PRIVATE_VOICE_ID,
          userId: 2,
          permissions: [
            ChannelPermission.VIEW_CHANNEL,
            ChannelPermission.SEND_MESSAGES
          ]
        })
      ).rejects.toThrow(
        'You cannot grant channel permissions that you do not have.'
      );

      await caller.channels.updatePermissions({
        channelId: PRIVATE_VOICE_ID,
        userId: 2,
        permissions: [ChannelPermission.VIEW_CHANNEL]
      });

      const { userPermissions } = await owner.channels.getPermissions({
        channelId: PRIVATE_VOICE_ID
      });
      const granted = userPermissions.filter(
        (row) => row.userId === 2 && row.allow
      );

      expect(granted.map((row) => row.permission)).toEqual([
        ChannelPermission.VIEW_CHANNEL
      ]);
    });
  });
});

describe('channels.markAsUnread', () => {
  test('should make the channel unread from the chosen message on', async () => {
    const { caller } = await initTest(2);
    const now = Date.now();

    const [, second] = await tdb
      .insert(messages)
      .values([
        { channelId: 1, userId: 1, content: '<p>one</p>', createdAt: now },
        { channelId: 1, userId: 1, content: '<p>two</p>', createdAt: now + 1 },
        { channelId: 1, userId: 1, content: '<p>three</p>', createdAt: now + 2 }
      ])
      .returning({ id: messages.id });

    await caller.channels.markAsRead({ channelId: 1 });
    await caller.channels.markAsUnread({ messageId: second!.id });

    const readStates = await getChannelsReadStatesForUser(2, 1);

    expect(readStates[1]).toBe(2);
  });

  test("should make every message unread from the channel's first one", async () => {
    const { caller } = await initTest(2);

    const first = await tdb
      .select({ id: messages.id })
      .from(messages)
      .where(eq(messages.channelId, 1))
      .orderBy(messages.id)
      .limit(1)
      .get();
    const total = await tdb
      .select({ id: messages.id })
      .from(messages)
      .where(eq(messages.channelId, 1));

    await caller.channels.markAsRead({ channelId: 1 });
    await caller.channels.markAsUnread({ messageId: first!.id });

    expect((await getChannelsReadStatesForUser(2, 1))[1]).toBe(total.length);
  });

  test("should tell the caller's other sessions", async () => {
    const { caller } = await initTest(2);
    const publishFor = spyOn(pubsub, 'publishFor');

    const first = await tdb
      .select({ id: messages.id })
      .from(messages)
      .where(eq(messages.channelId, 1))
      .limit(1)
      .get();

    await caller.channels.markAsUnread({ messageId: first!.id });

    expect(
      publishFor.mock.calls.some(
        ([, event]) => event === ServerEvents.CHANNEL_READ_STATES_UPDATE
      )
    ).toBe(true);
  });

  test('should refuse a message that does not exist', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.channels.markAsUnread({ messageId: 999_999 })
    ).rejects.toThrow('Message not found');
  });

  test('should refuse a message in a channel the caller cannot see', async () => {
    const { caller } = await initTest(2);
    const [hidden] = await tdb
      .insert(messages)
      .values({
        channelId: 5,
        userId: 1,
        content: '<p>hidden</p>',
        createdAt: Date.now()
      })
      .returning({ id: messages.id });

    // user 2 is denied viewing channel 5
    await expect(
      caller.channels.markAsUnread({ messageId: hidden!.id })
    ).rejects.toThrow('Insufficient channel permissions');
  });

  test('should refuse a reply inside a thread', async () => {
    const { caller } = await initTest(2);
    const now = Date.now();
    const [parent] = await tdb
      .insert(messages)
      .values({
        channelId: 1,
        userId: 1,
        content: '<p>parent</p>',
        createdAt: now
      })
      .returning({ id: messages.id });
    const [reply] = await tdb
      .insert(messages)
      .values({
        channelId: 1,
        userId: 1,
        content: '<p>reply</p>',
        parentMessageId: parent!.id,
        createdAt: now + 1
      })
      .returning({ id: messages.id });

    await expect(
      caller.channels.markAsUnread({ messageId: reply!.id })
    ).rejects.toThrow(
      'Only a message in the channel itself can be marked unread.'
    );
  });
});

describe('channels.getActivity', () => {
  test('should list when each visible channel last had a message', async () => {
    const { caller } = await initTest(1);

    const message = await tdb
      .select()
      .from(messages)
      .where(eq(messages.id, 1))
      .get();

    const activity = await caller.channels.getActivity();

    expect(activity).toEqual([
      { channelId: 1, lastMessageAt: message!.createdAt }
    ]);
  });

  test('should leave out direct messages and thread replies', async () => {
    const { caller } = await initTest(3);

    const message = await tdb
      .select()
      .from(messages)
      .where(eq(messages.id, 1))
      .get();

    await tdb.insert(messages).values({
      channelId: 1,
      userId: 3,
      content: 'a reply in a thread',
      parentMessageId: 1,
      createdAt: message!.createdAt + 60_000
    });

    const activity = await caller.channels.getActivity();

    expect(activity).toEqual([
      { channelId: 1, lastMessageAt: message!.createdAt }
    ]);
  });

  test('should leave out channels the caller cannot see', async () => {
    const { caller } = await initTest(2);

    await tdb.insert(messages).values({
      channelId: 5,
      userId: 1,
      content: 'in the restricted channel',
      createdAt: Date.now()
    });

    const activity = await caller.channels.getActivity();
    const channelIds = activity.map(({ channelId }) => channelId);

    expect(channelIds).toEqual([1]);
  });
});

describe('channels.getMembers', () => {
  test('should list everyone who can see a private channel', async () => {
    const { caller } = await initTest(1);

    const userIds = await caller.channels.getMembers({ channelId: 5 });

    expect(userIds.sort()).toEqual([1, 3, 4]);
  });

  test('should list both people in a direct message', async () => {
    const { caller } = await initTest(3);

    const userIds = await caller.channels.getMembers({ channelId: 3 });

    expect(userIds.sort()).toEqual([3, 4]);
  });

  test('should throw when the caller cannot see the channel', async () => {
    const { caller } = await initTest(2);

    await expect(caller.channels.getMembers({ channelId: 5 })).rejects.toThrow(
      'Insufficient channel permissions'
    );
  });

  test('should throw for a direct message the caller is not in', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.channels.getMembers({ channelId: 3 })
    ).rejects.toThrow();
  });

  test('should reject an invalid channel id', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.channels.getMembers({ channelId: 0 })
    ).rejects.toThrow();
  });
});

describe('channels.setPinned', () => {
  test('should pin channels in the order pinned and unpin them', async () => {
    const { caller } = await initTest(1);

    await caller.channels.setPinned({ channelId: 2, pinned: true });
    await caller.channels.setPinned({ channelId: 1, pinned: true });

    expect(await caller.channels.getPins()).toEqual([2, 1]);

    await caller.channels.setPinned({ channelId: 2, pinned: false });

    expect(await caller.channels.getPins()).toEqual([1]);
  });

  test('should keep a pin in its place when pinned again', async () => {
    const { caller } = await initTest(1);

    await caller.channels.setPinned({ channelId: 1, pinned: true });
    await caller.channels.setPinned({ channelId: 2, pinned: true });
    await caller.channels.setPinned({ channelId: 1, pinned: true });

    expect(await caller.channels.getPins()).toEqual([1, 2]);
  });

  test("should only list the caller's own pins", async () => {
    const { caller: owner } = await initTest(1);
    const { caller: member } = await initTest(2);

    await owner.channels.setPinned({ channelId: 1, pinned: true });

    expect(await member.channels.getPins()).toEqual([]);
  });

  test("should tell the caller's other devices", async () => {
    const { caller } = await initTest(1);
    const publishFor = spyOn(pubsub, 'publishFor');

    await caller.channels.setPinned({ channelId: 1, pinned: true });

    expect(publishFor).toHaveBeenCalledWith(
      1,
      ServerEvents.CHANNEL_PINS_UPDATE,
      [1]
    );
  });

  test('should drop the pin with its channel', async () => {
    const { caller } = await initTest(1);

    await caller.channels.setPinned({ channelId: 1, pinned: true });
    await caller.channels.delete({ channelId: 1 });

    expect(await caller.channels.getPins()).toEqual([]);
  });

  test('should refuse a channel the caller cannot see', async () => {
    const { caller } = await initTest(2);

    // user 2 is denied viewing channel 5
    await expect(
      caller.channels.setPinned({ channelId: 5, pinned: true })
    ).rejects.toThrow('Insufficient channel permissions');
  });

  test('should refuse a direct message the caller is not in', async () => {
    const { caller } = await initTest(5);

    // channel 3 is the dm between users 3 and 4
    await expect(
      caller.channels.setPinned({ channelId: 3, pinned: true })
    ).rejects.toThrow();
  });

  test('should refuse a channel id that is not positive', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.channels.setPinned({ channelId: 0, pinned: true })
    ).rejects.toThrow();
  });
});
