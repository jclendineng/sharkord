import { SettingsSection } from '@/components/server-screens/settings-shell/section';
import { useSettingsForm } from '@/components/server-screens/settings-shell/use-settings-form';
import { useAdminChannelGeneral } from '@/features/server/admin/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { CHANNEL_RETENTION_OPTIONS_DAYS } from '@sharkord/shared';
import {
  Group,
  Input,
  LoadingCard,
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Switch,
  Textarea
} from '@sharkord/ui';
import { memo, useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';

type TGeneralProps = {
  channelId: number;
};

// a number of days, or KEEP_FOREVER
type TChannelValues = {
  name: string;
  topic: string;
  private: boolean;
  retentionDays: string;
};

const KEEP_FOREVER = 'forever';

const General = memo(({ channelId }: TGeneralProps) => {
  const { t } = useTranslation('settings');
  const { channel, loading } = useAdminChannelGeneral(channelId);

  const onSave = useCallback(
    async (values: TChannelValues) => {
      const trpc = getTRPCClient();

      await trpc.channels.update.mutate({
        channelId,
        name: values.name,
        topic: values.topic || null,
        private: values.private,
        retentionDays:
          values.retentionDays === KEEP_FOREVER
            ? null
            : Number(values.retentionDays)
      });
    },
    [channelId]
  );

  const { r, values, onChange, reset } = useSettingsForm<TChannelValues>({
    initialValues: {
      name: '',
      topic: '',
      private: false,
      retentionDays: KEEP_FOREVER
    },
    onSave,
    successMessage: t('channelUpdated'),
    errorMessage: t('failedUpdateChannel')
  });

  useEffect(() => {
    if (!channel) return;

    reset({
      name: channel.name,
      topic: channel.topic ?? '',
      private: channel.private,
      retentionDays:
        channel.retentionDays === null
          ? KEEP_FOREVER
          : String(channel.retentionDays)
    });
  }, [channel, reset]);

  const [previewCount, setPreviewCount] = useState<number>();
  const retentionChoice = values.retentionDays;

  // the dry run: how many messages the chosen period would delete if it ran now
  useEffect(() => {
    if (retentionChoice === KEEP_FOREVER) {
      setPreviewCount(undefined);
      return;
    }

    let isCurrent = true;

    const loadPreview = async () => {
      try {
        const trpc = getTRPCClient();
        const total = await trpc.channels.getRetentionPreview.query({
          channelId,
          retentionDays: Number(retentionChoice)
        });

        if (isCurrent) setPreviewCount(total);
      } catch {
        if (isCurrent) setPreviewCount(undefined);
      }
    };

    loadPreview();

    return () => {
      isCurrent = false;
    };
  }, [channelId, retentionChoice]);

  const handleRetentionChange = useCallback(
    (value: string) => onChange('retentionDays', value),
    [onChange]
  );

  const handlePrivateChange = useCallback(
    (value: boolean) => onChange('private', value),
    [onChange]
  );

  if (loading) {
    return <LoadingCard className="h-64" />;
  }

  return (
    <SettingsSection
      title={t('channelInfoTitle')}
      description={t('channelInfoDesc')}
    >
      <Group label={t('channelNameLabel')}>
        <Input placeholder={t('channelNamePlaceholder')} {...r('name')} />
      </Group>

      <Group label={t('channelTopicLabel')}>
        <Textarea placeholder={t('channelTopicPlaceholder')} {...r('topic')} />
      </Group>

      <Group label={t('privateLabel')} description={t('privateDesc')}>
        <Switch
          checked={values.private}
          onCheckedChange={handlePrivateChange}
        />
      </Group>

      <Group label={t('retentionLabel')} description={t('retentionDesc')}>
        <Select
          value={values.retentionDays}
          onValueChange={handleRetentionChange}
        >
          <SelectTrigger className="w-64">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectGroup>
              <SelectItem value={KEEP_FOREVER}>
                {t('retentionForever')}
              </SelectItem>
              {CHANNEL_RETENTION_OPTIONS_DAYS.map((days) => (
                <SelectItem key={days} value={String(days)}>
                  {t('retentionDays', { count: days })}
                </SelectItem>
              ))}
            </SelectGroup>
          </SelectContent>
        </Select>
        {previewCount !== undefined && (
          <span className="text-sm text-muted-foreground">
            {t('retentionPreview', { count: previewCount })}
          </span>
        )}
      </Group>
    </SettingsSection>
  );
});

export { General };
