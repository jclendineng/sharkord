import { Permission } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';
import { desc, eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb, testsBaseUrl } from '../../__tests__/setup';
import { messages, rolePermissions, webhooks } from '../../db/schema';

// seeded: General (1) a text channel, DM Channel (3) between users 3 and 4
const CHANNEL_ID = 1;
const DM_CHANNEL_ID = 3;

const createWebhook = async (name = 'GitHub') => {
  const { caller } = await initTest(1);

  return caller.webhooks.add({ channelId: CHANNEL_ID, name });
};

const post = (id: number, token: string, body: unknown) =>
  fetch(`${testsBaseUrl}/webhooks/${id}/${token}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });

const latestMessage = () =>
  tdb
    .select()
    .from(messages)
    .where(eq(messages.channelId, CHANNEL_ID))
    .orderBy(desc(messages.id))
    .limit(1)
    .get();

describe('webhooks router', () => {
  test('should create a webhook and list it without its token', async () => {
    const { caller } = await initTest(1);
    const { id, token } = await caller.webhooks.add({
      channelId: CHANNEL_ID,
      name: 'GitHub'
    });

    const listed = await caller.webhooks.getAll({ channelId: CHANNEL_ID });
    const stored = await tdb
      .select()
      .from(webhooks)
      .where(eq(webhooks.id, id))
      .get();

    expect(token.length).toBeGreaterThan(20);
    expect(listed.map(({ id, name }) => ({ id, name }))).toEqual([
      { id, name: 'GitHub' }
    ]);
    expect(listed[0]).not.toHaveProperty('tokenHash');
    expect(stored?.tokenHash).not.toBe(token);
  });

  test('should refuse someone without MANAGE_CHANNELS', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.webhooks.add({ channelId: CHANNEL_ID, name: 'GitHub' })
    ).rejects.toThrow('Insufficient permissions');
    await expect(
      caller.webhooks.getAll({ channelId: CHANNEL_ID })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should refuse a webhook in a direct message', async () => {
    await tdb.insert(rolePermissions).values({
      roleId: 2,
      permission: Permission.MANAGE_CHANNELS,
      createdAt: Date.now()
    });

    const { caller } = await initTest(3);

    await expect(
      caller.webhooks.add({ channelId: DM_CHANNEL_ID, name: 'GitHub' })
    ).rejects.toThrow('Direct messages cannot have webhooks.');
  });

  test('should refuse a name that is empty or too long', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.webhooks.add({ channelId: CHANNEL_ID, name: '  ' })
    ).rejects.toThrow();
    await expect(
      caller.webhooks.add({ channelId: CHANNEL_ID, name: 'x'.repeat(40) })
    ).rejects.toThrow();
  });

  test('should delete a webhook, and say when there is none', async () => {
    const { caller } = await initTest(1);
    const { id } = await createWebhook();

    await caller.webhooks.delete({ webhookId: id });

    expect(await tdb.select().from(webhooks)).toEqual([]);
    await expect(caller.webhooks.delete({ webhookId: id })).rejects.toThrow(
      'Webhook not found.'
    );
  });
});

describe('/webhooks', () => {
  test('should post plain text under the webhook name', async () => {
    const { id, token } = await createWebhook();

    const response = await post(id, token, {
      content: 'build passed <b>ok</b>\nsecond line'
    });
    const message = await latestMessage();

    expect(response.status).toBe(204);
    expect(message?.webhookName).toBe('GitHub');
    expect(message?.userId).toBeNull();
    expect(message?.content).toContain('&lt;b&gt;ok&lt;/b&gt;');
    expect(message?.content).toContain('<p>second line</p>');
  });

  test('should post under a username given with the message', async () => {
    const { id, token } = await createWebhook();

    await post(id, token, { content: 'deployed', username: 'CI' });

    const message = await latestMessage();

    expect(message?.webhookName).toBe('CI');
  });

  test('should refuse a wrong token or an unknown webhook alike', async () => {
    const { id } = await createWebhook();

    const wrongToken = await post(id, 'not-the-token', { content: 'hi' });
    const unknown = await post(99999, 'not-the-token', { content: 'hi' });

    expect(wrongToken.status).toBe(404);
    expect(unknown.status).toBe(404);
  });

  test('should refuse an empty message', async () => {
    const { id, token } = await createWebhook();

    const response = await post(id, token, { content: '   ' });

    expect(response.status).toBe(400);
  });
});
