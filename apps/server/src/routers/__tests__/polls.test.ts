import { Permission } from '@sharkord/shared';
import { describe, expect, spyOn, test } from 'bun:test';
import { and, eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { config } from '../../config';
import {
  messages,
  pollAnswers,
  polls,
  pollVotes,
  pushDevices,
  rolePermissions
} from '../../db/schema';
import { drainPushNotificationsQueue } from '../../queues/push-notifications';
import * as apns from '../../utils/apns';

const createPoll = async (
  userId = 1,
  overrides: Partial<{
    channelId: number;
    allowMultiple: boolean;
    answers: { text: string; emoji?: string }[];
  }> = {}
) => {
  const { caller } = await initTest(userId);

  return caller.polls.create({
    channelId: overrides.channelId ?? 1,
    question: 'Pizza or tacos?',
    answers: overrides.answers ?? [
      { text: 'Pizza', emoji: '🍕' },
      { text: 'Tacos' }
    ],
    durationHours: 24,
    allowMultiple: overrides.allowMultiple ?? false
  });
};

const answerIdsOf = async (messageId: number) =>
  (
    await tdb
      .select({ id: pollAnswers.id })
      .from(pollAnswers)
      .where(eq(pollAnswers.messageId, messageId))
      .orderBy(pollAnswers.position)
  ).map(({ id }) => id);

const votesOf = async (messageId: number, userId: number) =>
  (
    await tdb
      .select({ answerId: pollVotes.answerId })
      .from(pollVotes)
      .where(
        and(eq(pollVotes.messageId, messageId), eq(pollVotes.userId, userId))
      )
  )
    .map(({ answerId }) => answerId)
    .sort();

describe('polls.create', () => {
  test('should store the poll as a message with its answers in order', async () => {
    const before = Date.now();
    const messageId = await createPoll();

    const message = await tdb
      .select()
      .from(messages)
      .where(eq(messages.id, messageId))
      .get();

    expect(message).toMatchObject({
      channelId: 1,
      userId: 1,
      content: '',
      editable: false
    });

    const poll = await tdb
      .select()
      .from(polls)
      .where(eq(polls.messageId, messageId))
      .get();

    expect(poll).toMatchObject({
      question: 'Pizza or tacos?',
      allowMultiple: false,
      endedAt: null
    });
    expect(poll!.expiresAt).toBeGreaterThanOrEqual(
      before + 24 * 60 * 60 * 1000
    );

    const answers = await tdb
      .select({
        text: pollAnswers.text,
        emoji: pollAnswers.emoji,
        position: pollAnswers.position
      })
      .from(pollAnswers)
      .where(eq(pollAnswers.messageId, messageId))
      .orderBy(pollAnswers.position);

    expect(answers).toEqual([
      { text: 'Pizza', emoji: '🍕', position: 0 },
      { text: 'Tacos', emoji: null, position: 1 }
    ]);
  });

  test('should come back with the message, votes included', async () => {
    const messageId = await createPoll();
    const [pizza] = await answerIdsOf(messageId);
    const { caller } = await initTest(2);

    await caller.polls.vote({ messageId, answerIds: [pizza!] });

    const page = await caller.messages.get({
      channelId: 1,
      cursor: null,
      limit: 50
    });
    const message = page.messages.find(({ id }) => id === messageId);

    expect(message?.poll).toMatchObject({
      question: 'Pizza or tacos?',
      allowMultiple: false,
      endedAt: null,
      answers: [
        { id: pizza, text: 'Pizza', emoji: '🍕', userIds: [2] },
        { text: 'Tacos', emoji: null, userIds: [] }
      ]
    });

    const plain = page.messages.find(({ id }) => id !== messageId);

    expect(plain?.poll).toBeNull();
  });

  test('should push the question to the other side of a direct message', async () => {
    const original = config.push.enabled;

    config.push.enabled = true;

    const { caller: userB } = await initTest(4);

    await userB.notifications.registerDevice({
      token: '4'.padStart(64, 'a'),
      sandbox: false
    });

    const spy = spyOn(apns, 'sendApnsNotification').mockResolvedValue({
      status: 200
    });

    try {
      await createPoll(3, { channelId: 3 });
      await drainPushNotificationsQueue();
    } finally {
      config.push.enabled = original;
    }

    const [[notification]] = spy.mock.calls as unknown as [
      [apns.TApnsNotification]
    ];

    expect(notification.payload).toMatchObject({
      aps: { alert: { body: 'Poll: Pizza or tacos?' } }
    });

    expect(await tdb.select().from(pushDevices)).toHaveLength(1);
  });

  test('should refuse someone without permission to send messages', async () => {
    await tdb
      .delete(rolePermissions)
      .where(
        and(
          eq(rolePermissions.roleId, 2),
          eq(rolePermissions.permission, Permission.SEND_MESSAGES)
        )
      );

    await expect(createPoll(2)).rejects.toThrow('Insufficient permissions');
    expect(await tdb.select().from(polls)).toHaveLength(0);
  });

  test('should refuse a channel the caller cannot post in', async () => {
    await expect(createPoll(2, { channelId: 5 })).rejects.toThrow(
      'Insufficient channel permissions'
    );
  });

  test('should refuse a direct message the caller is not part of', async () => {
    await expect(createPoll(2, { channelId: 3 })).rejects.toThrow(
      'Insufficient channel permissions'
    );
  });

  test('should refuse answers that repeat', async () => {
    await expect(
      createPoll(1, { answers: [{ text: 'Pizza' }, { text: 'pizza' }] })
    ).rejects.toThrow('Each answer has to be different.');
  });

  test('should refuse a length that is not offered', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.polls.create({
        channelId: 1,
        question: 'How long?',
        answers: [{ text: 'Long' }],
        durationHours: 5,
        allowMultiple: false
      })
    ).rejects.toThrow('That poll length is not available.');
  });

  test('should refuse an empty question, no answers, too many or too long ones', async () => {
    const { caller } = await initTest(1);
    const base = { channelId: 1, durationHours: 24, allowMultiple: false };

    await expect(
      caller.polls.create({
        ...base,
        question: '   ',
        answers: [{ text: 'A' }]
      })
    ).rejects.toThrow();

    await expect(
      caller.polls.create({ ...base, question: 'Q', answers: [] })
    ).rejects.toThrow();

    await expect(
      caller.polls.create({
        ...base,
        question: 'Q',
        answers: Array.from({ length: 11 }, (_, index) => ({
          text: `Answer ${index}`
        }))
      })
    ).rejects.toThrow();

    await expect(
      caller.polls.create({
        ...base,
        question: 'Q',
        answers: [{ text: 'x'.repeat(56) }]
      })
    ).rejects.toThrow();

    expect(await tdb.select().from(polls)).toHaveLength(0);
  });

  test('should go with the message when it is deleted', async () => {
    const messageId = await createPoll();
    const [pizza] = await answerIdsOf(messageId);
    const { caller } = await initTest(1);

    await caller.polls.vote({ messageId, answerIds: [pizza!] });
    await caller.messages.delete({ messageId });

    expect(await tdb.select().from(polls)).toHaveLength(0);
    expect(await tdb.select().from(pollAnswers)).toHaveLength(0);
    expect(await tdb.select().from(pollVotes)).toHaveLength(0);
  });
});

describe('polls.vote', () => {
  test('should record a vote and replace it with a new one', async () => {
    const messageId = await createPoll();
    const [pizza, tacos] = await answerIdsOf(messageId);
    const { caller } = await initTest(2);

    await caller.polls.vote({ messageId, answerIds: [pizza!] });
    expect(await votesOf(messageId, 2)).toEqual([pizza!]);

    await caller.polls.vote({ messageId, answerIds: [tacos!] });
    expect(await votesOf(messageId, 2)).toEqual([tacos!]);
  });

  test('should take a vote back when given no answers', async () => {
    const messageId = await createPoll();
    const [pizza] = await answerIdsOf(messageId);
    const { caller } = await initTest(2);

    await caller.polls.vote({ messageId, answerIds: [pizza!] });
    await caller.polls.vote({ messageId, answerIds: [] });

    expect(await votesOf(messageId, 2)).toEqual([]);
  });

  test('should take several answers when the poll allows it', async () => {
    const messageId = await createPoll(1, { allowMultiple: true });
    const answerIds = await answerIdsOf(messageId);
    const { caller } = await initTest(2);

    await caller.polls.vote({ messageId, answerIds });

    expect(await votesOf(messageId, 2)).toEqual([...answerIds].sort());
  });

  test('should refuse several answers on a single answer poll', async () => {
    const messageId = await createPoll();
    const answerIds = await answerIdsOf(messageId);
    const { caller } = await initTest(2);

    await expect(caller.polls.vote({ messageId, answerIds })).rejects.toThrow(
      'This poll takes a single answer.'
    );
    expect(await votesOf(messageId, 2)).toEqual([]);
  });

  test("should refuse another poll's answer", async () => {
    const first = await createPoll();
    const second = await createPoll();
    const [otherAnswer] = await answerIdsOf(second);
    const { caller } = await initTest(2);

    await expect(
      caller.polls.vote({ messageId: first, answerIds: [otherAnswer!] })
    ).rejects.toThrow('That answer is not part of this poll.');
  });

  test('should refuse a poll that was ended', async () => {
    const messageId = await createPoll();
    const [pizza] = await answerIdsOf(messageId);
    const { caller: owner } = await initTest(1);
    const { caller } = await initTest(2);

    await owner.polls.end({ messageId });

    await expect(
      caller.polls.vote({ messageId, answerIds: [pizza!] })
    ).rejects.toThrow('This poll has ended.');
  });

  test('should refuse a poll past its time', async () => {
    const messageId = await createPoll();
    const [pizza] = await answerIdsOf(messageId);
    const { caller } = await initTest(2);

    await tdb
      .update(polls)
      .set({ expiresAt: Date.now() - 1000 })
      .where(eq(polls.messageId, messageId));

    await expect(
      caller.polls.vote({ messageId, answerIds: [pizza!] })
    ).rejects.toThrow('This poll has ended.');
  });

  test('should refuse a message without a poll', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.polls.vote({ messageId: 1, answerIds: [] })
    ).rejects.toThrow('This message has no poll.');
  });

  test('should refuse a message that does not exist', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.polls.vote({ messageId: 9999, answerIds: [] })
    ).rejects.toThrow('Message not found');
  });

  test('should refuse a poll in a channel the caller cannot see', async () => {
    const messageId = await createPoll(1, { channelId: 5 });
    const { caller } = await initTest(2);

    await expect(
      caller.polls.vote({ messageId, answerIds: [] })
    ).rejects.toThrow('Insufficient channel permissions');
  });

  test('should refuse a poll in a direct message the caller is not part of', async () => {
    const messageId = await createPoll(3, { channelId: 3 });
    const { caller } = await initTest(2);

    await expect(
      caller.polls.vote({ messageId, answerIds: [] })
    ).rejects.toThrow('You are not a participant in this DM channel');
  });
});

describe('polls.end', () => {
  test('should let the author end their poll', async () => {
    const messageId = await createPoll(2);
    const { caller } = await initTest(2);

    await caller.polls.end({ messageId });

    const poll = await tdb
      .select()
      .from(polls)
      .where(eq(polls.messageId, messageId))
      .get();

    expect(poll?.endedAt).toBeNumber();
  });

  test("should let someone who manages messages end another's poll", async () => {
    const messageId = await createPoll(2);
    const { caller } = await initTest(1);

    await caller.polls.end({ messageId });

    const poll = await tdb
      .select()
      .from(polls)
      .where(eq(polls.messageId, messageId))
      .get();

    expect(poll?.endedAt).toBeNumber();
  });

  test("should refuse ending someone else's poll", async () => {
    const messageId = await createPoll(1);
    const { caller } = await initTest(2);

    await expect(caller.polls.end({ messageId })).rejects.toThrow(
      'You do not have permission to end this poll'
    );

    const poll = await tdb
      .select()
      .from(polls)
      .where(eq(polls.messageId, messageId))
      .get();

    expect(poll?.endedAt).toBeNull();
  });

  test('should refuse a poll that already ended', async () => {
    const messageId = await createPoll();
    const { caller } = await initTest(1);

    await caller.polls.end({ messageId });

    await expect(caller.polls.end({ messageId })).rejects.toThrow(
      'This poll has ended.'
    );
  });

  test('should refuse a message without a poll', async () => {
    const { caller } = await initTest(1);

    await expect(caller.polls.end({ messageId: 1 })).rejects.toThrow(
      'This message has no poll.'
    );
  });
});
