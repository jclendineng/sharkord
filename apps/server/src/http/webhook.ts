import {
  WEBHOOK_CONTENT_MAX_LENGTH,
  WEBHOOK_NAME_MAX_LENGTH
} from '@sharkord/shared';
import http from 'http';
import z from 'zod';
import { config } from '../config';
import { getWebhookById } from '../db/queries/webhooks';
import { matchesWebhookToken, postWebhookMessage } from '../helpers/webhooks';
import { createRateLimiter } from '../utils/rate-limiters/rate-limiter';
import { enforceHttpRateLimit, getJsonBody, sendJsonError } from './helpers';

const zBody = z.object({
  content: z.string().trim().min(1).max(WEBHOOK_CONTENT_MAX_LENGTH),
  username: z.string().trim().min(1).max(WEBHOOK_NAME_MAX_LENGTH).optional()
});

const webhookRateLimiter = createRateLimiter({
  maxRequests: config.rateLimiters.webhook.maxRequests,
  windowMs: config.rateLimiters.webhook.windowMs
});

// pre-auth on purpose: whoever holds the url may post, the token in it is the credential.
// a wrong id and a wrong token get the same answer, so the url cannot be probed for ids
const webhookRouteHandler = async (
  req: http.IncomingMessage,
  res: http.ServerResponse,
  { url, info }: { url: URL; info: { ip?: string } | undefined }
) => {
  const allowed = enforceHttpRateLimit(res, webhookRateLimiter, info?.ip, {
    route: '/webhooks',
    message: 'Too many messages. Please try again shortly.'
  });

  if (!allowed) return;

  const [, , idSegment, token] = url.pathname.split('/');
  const webhookId = Number(idSegment);
  const webhook =
    Number.isInteger(webhookId) && webhookId > 0
      ? await getWebhookById(webhookId)
      : undefined;

  if (!webhook || !token || !(await matchesWebhookToken(webhook, token))) {
    req.resume();
    sendJsonError(res, 404, 'Unknown webhook');
    return;
  }

  const data = zBody.parse(await getJsonBody(req));

  await postWebhookMessage(webhook, data);

  res.writeHead(204);
  res.end();
};

export { webhookRouteHandler };
