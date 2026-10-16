import { SettingsSection } from '@/components/server-screens/settings-shell/section';
import { requestConfirmation } from '@/features/dialogs/actions';
import { getUrlFromServer } from '@/helpers/get-file-url';
import { getTRPCClient } from '@/lib/trpc';
import { getTrpcError, WEBHOOK_NAME_MAX_LENGTH } from '@sharkord/shared';
import { Button, Group, Input } from '@sharkord/ui';
import { Copy, Trash } from 'lucide-react';
import { memo, useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TWebhookRow = {
  id: number;
  name: string;
  createdAt: number;
};

type TWebhookItemProps = {
  webhook: TWebhookRow;
  onDelete: (webhook: TWebhookRow) => void;
};

const WebhookItem = memo(({ webhook, onDelete }: TWebhookItemProps) => {
  const { t } = useTranslation('settings');

  const handleDelete = useCallback(() => {
    onDelete(webhook);
  }, [onDelete, webhook]);

  return (
    <div className="flex items-center justify-between rounded-md border border-border px-3 py-2">
      <span className="truncate text-sm">{webhook.name}</span>
      <Button
        variant="ghost"
        size="sm"
        onClick={handleDelete}
        aria-label={t('deleteWebhookBtn')}
      >
        <Trash className="size-4" />
      </Button>
    </div>
  );
});

type TWebhooksProps = {
  channelId: number;
};

const Webhooks = memo(({ channelId }: TWebhooksProps) => {
  const { t } = useTranslation('settings');
  const [webhooks, setWebhooks] = useState<TWebhookRow[]>([]);
  const [name, setName] = useState('');
  const [newUrl, setNewUrl] = useState<string>();
  const [isCreating, setIsCreating] = useState(false);

  const load = useCallback(async () => {
    try {
      const trpc = getTRPCClient();

      setWebhooks(await trpc.webhooks.getAll.query({ channelId }));
    } catch (error) {
      toast.error(getTrpcError(error, t('failedLoadWebhooks')));
    }
  }, [channelId, t]);

  useEffect(() => {
    load();
  }, [load]);

  const onNameChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setName(event.target.value);
    },
    []
  );

  const onCreate = useCallback(async () => {
    setIsCreating(true);

    try {
      const trpc = getTRPCClient();
      const { id, token } = await trpc.webhooks.add.mutate({
        channelId,
        name
      });

      // shown this once, the server keeps only a hash of the token
      setNewUrl(`${getUrlFromServer()}/webhooks/${id}/${token}`);
      setName('');
      await load();
    } catch (error) {
      toast.error(getTrpcError(error, t('failedCreateWebhook')));
    } finally {
      setIsCreating(false);
    }
  }, [channelId, name, load, t]);

  const onCopy = useCallback(async () => {
    if (!newUrl) return;

    try {
      await navigator.clipboard.writeText(newUrl);
      toast.success(t('webhookUrlCopied'));
    } catch {
      toast.error(t('failedCopyWebhookUrl'));
    }
  }, [newUrl, t]);

  const onDelete = useCallback(
    async (webhook: TWebhookRow) => {
      const confirmed = await requestConfirmation({
        title: t('deleteWebhookTitle'),
        message: t('deleteWebhookMsg', { name: webhook.name }),
        confirmLabel: t('deleteWebhookBtn'),
        variant: 'danger'
      });

      if (!confirmed) return;

      try {
        const trpc = getTRPCClient();

        await trpc.webhooks.delete.mutate({ webhookId: webhook.id });
        await load();
      } catch (error) {
        toast.error(getTrpcError(error, t('failedDeleteWebhook')));
      }
    },
    [load, t]
  );

  return (
    <SettingsSection title={t('webhooksTitle')} description={t('webhooksDesc')}>
      <Group label={t('webhookNameLabel')}>
        <div className="flex gap-2">
          <Input
            value={name}
            onChange={onNameChange}
            maxLength={WEBHOOK_NAME_MAX_LENGTH}
            placeholder={t('webhookNamePlaceholder')}
          />
          <Button onClick={onCreate} disabled={isCreating || !name.trim()}>
            {t('createWebhookBtn')}
          </Button>
        </div>
      </Group>

      {newUrl && (
        <Group label={t('webhookUrlLabel')} description={t('webhookUrlDesc')}>
          <div className="flex gap-2">
            <Input value={newUrl} readOnly />
            <Button variant="secondary" onClick={onCopy}>
              <Copy className="size-4" />
            </Button>
          </div>
        </Group>
      )}

      <div className="space-y-2">
        {webhooks.length === 0 && (
          <p className="text-sm text-muted-foreground">{t('noWebhooks')}</p>
        )}
        {webhooks.map((webhook) => (
          <WebhookItem key={webhook.id} webhook={webhook} onDelete={onDelete} />
        ))}
      </div>
    </SettingsSection>
  );
});

export { Webhooks };
