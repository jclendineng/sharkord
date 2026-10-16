import { eq } from 'drizzle-orm';
import { db } from '..';
import { webhooks } from '../schema';

// what the settings screen lists, never the token hash
const getWebhooksForChannel = async (channelId: number) =>
  db
    .select({
      id: webhooks.id,
      channelId: webhooks.channelId,
      name: webhooks.name,
      createdBy: webhooks.createdBy,
      createdAt: webhooks.createdAt
    })
    .from(webhooks)
    .where(eq(webhooks.channelId, channelId));

const getWebhookById = async (webhookId: number) =>
  db.select().from(webhooks).where(eq(webhooks.id, webhookId)).limit(1).get();

export { getWebhookById, getWebhooksForChannel };
