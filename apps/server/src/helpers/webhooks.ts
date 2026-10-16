import {
  getPlainTextFromHtml,
  isEmptyMessage,
  prepareMessageHtml,
  sha256
} from '@sharkord/shared';
import { randomBytes, timingSafeEqual } from 'crypto';
import { eq } from 'drizzle-orm';
import { db } from '../db';
import { publishMessage } from '../db/publishers';
import { messages, webhooks } from '../db/schema';
import { eventBus } from '../plugins/event-bus';
import { enqueueProcessMetadata } from '../queues/message-metadata';
import { enqueuePushNotification } from '../queues/push-notifications';
import { invariant } from '../utils/invariant';
import { sanitizeMessageHtml } from './sanitize-html';

type TWebhook = typeof webhooks.$inferSelect;

const escapeHtml = (text: string) =>
  text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

// a post is plain text, a paragraph a line, the way the composer writes it, with its links made
// clickable. nothing a caller sends is taken as html
const textToMessageHtml = (text: string) =>
  prepareMessageHtml(
    text
      .split('\n')
      .map((line) => `<p>${escapeHtml(line)}</p>`)
      .join('')
  );

const createWebhook = async (
  channelId: number,
  name: string,
  createdBy: number
): Promise<{ webhook: TWebhook; token: string }> => {
  const token = randomBytes(32).toString('base64url');

  const webhook = await db
    .insert(webhooks)
    .values({
      channelId,
      name,
      tokenHash: await sha256(token),
      createdBy,
      createdAt: Date.now()
    })
    .returning()
    .get();

  return { webhook, token };
};

const deleteWebhook = async (webhookId: number) => {
  await db.delete(webhooks).where(eq(webhooks.id, webhookId));
};

const matchesWebhookToken = async (webhook: TWebhook, token: string) => {
  const expected = Buffer.from(webhook.tokenHash);
  const given = Buffer.from(await sha256(token));

  return expected.length === given.length && timingSafeEqual(expected, given);
};

const postWebhookMessage = async (
  webhook: TWebhook,
  { content, username }: { content: string; username?: string }
) => {
  const sanitizedContent = sanitizeMessageHtml(textToMessageHtml(content));

  invariant(!isEmptyMessage(sanitizedContent), {
    code: 'BAD_REQUEST',
    message: 'The message is empty.'
  });

  const message = await db
    .insert(messages)
    .values({
      channelId: webhook.channelId,
      userId: null,
      pluginId: null,
      webhookName: username ?? webhook.name,
      content: sanitizedContent,
      editable: false,
      createdAt: Date.now()
    })
    .returning()
    .get();

  publishMessage(message.id, webhook.channelId, 'create');
  enqueueProcessMetadata(sanitizedContent, message.id);
  enqueuePushNotification(message.id);

  eventBus.emit('message:created', {
    messageId: message.id,
    channelId: webhook.channelId,
    userId: null,
    pluginId: null,
    content: sanitizedContent,
    textContent: getPlainTextFromHtml(sanitizedContent),
    parentMessageId: null,
    replyToMessageId: null,
    fileIds: []
  });

  return message.id;
};

export {
  createWebhook,
  deleteWebhook,
  matchesWebhookToken,
  postWebhookMessage
};
