import { t } from '../../utils/trpc';
import { addWebhookRoute } from './add-webhook';
import { deleteWebhookRoute } from './delete-webhook';
import { getWebhooksRoute } from './get-webhooks';

export const webhooksRouter = t.router({
  getAll: getWebhooksRoute,
  add: addWebhookRoute,
  delete: deleteWebhookRoute
});
