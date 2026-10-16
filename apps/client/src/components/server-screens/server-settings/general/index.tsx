import { ImagePicker } from '@/components/image-picker';
import { SettingsSection } from '@/components/server-screens/settings-shell/section';
import { useSettingsForm } from '@/components/server-screens/settings-shell/use-settings-form';
import { useAdminGeneral } from '@/features/server/admin/hooks';
import { useChannels } from '@/features/server/channels/hooks';
import { getFileUrl } from '@/helpers/get-file-url';
import type { TPickedImage } from '@/hooks/use-pick-image';
import { getTRPCClient } from '@/lib/trpc';
import {
  AFK_TIMEOUT_DEFAULT_SECONDS,
  AFK_TIMEOUT_OPTIONS_SECONDS,
  ChannelType
} from '@sharkord/shared';
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
import { memo, useCallback, useEffect, useMemo } from 'react';
import { useTranslation } from 'react-i18next';

type TServerGeneralValues = {
  name: string;
  description: string;
  password: string;
  onlyAskForPasswordOnFirstJoin: boolean;
  allowNewUsers: boolean;
  directMessagesEnabled: boolean;
  enablePlugins: boolean;
  webRtcSimulcastEnabled: boolean;
  enableSearch: boolean;
  showWelcomeDialog: boolean;
  pushShowMessageContent: boolean;
  linkPreviewsPrivateNetwork: boolean;
  reportEmail: string;
  klipyApiKey: string;
  freesoundApiKey: string;
  // a channel id, or AFK_OFF
  afkChannelId: string;
  afkTimeoutSeconds: string;
  // undefined means untouched, null means remove
  logo?: TPickedImage | null;
};

const AFK_OFF = 'off';

const INITIAL_VALUES: TServerGeneralValues = {
  name: '',
  description: '',
  password: '',
  onlyAskForPasswordOnFirstJoin: false,
  allowNewUsers: false,
  directMessagesEnabled: true,
  enablePlugins: false,
  webRtcSimulcastEnabled: false,
  enableSearch: true,
  showWelcomeDialog: true,
  pushShowMessageContent: true,
  linkPreviewsPrivateNetwork: false,
  reportEmail: '',
  klipyApiKey: '',
  freesoundApiKey: '',
  afkChannelId: AFK_OFF,
  afkTimeoutSeconds: String(AFK_TIMEOUT_DEFAULT_SECONDS)
};

const General = memo(() => {
  const { t } = useTranslation('settings');
  const { settings, loading } = useAdminGeneral();

  const onSave = useCallback(async (values: TServerGeneralValues) => {
    const trpc = getTRPCClient();

    await trpc.others.updateSettings.mutate({
      name: values.name,
      description: values.description,
      password: values.password || null,
      onlyAskForPasswordOnFirstJoin: values.onlyAskForPasswordOnFirstJoin,
      allowNewUsers: values.allowNewUsers,
      directMessagesEnabled: values.directMessagesEnabled,
      enablePlugins: values.enablePlugins,
      webRtcSimulcastEnabled: values.webRtcSimulcastEnabled,
      enableSearch: values.enableSearch,
      showWelcomeDialog: values.showWelcomeDialog,
      pushShowMessageContent: values.pushShowMessageContent,
      linkPreviewsPrivateNetwork: values.linkPreviewsPrivateNetwork,
      reportEmail: values.reportEmail.trim() || null,
      klipyApiKey: values.klipyApiKey.trim() || null,
      freesoundApiKey: values.freesoundApiKey.trim() || null,
      afkChannelId:
        values.afkChannelId === AFK_OFF ? null : Number(values.afkChannelId),
      afkTimeoutSeconds: Number(values.afkTimeoutSeconds)
    });

    if (values.logo !== undefined) {
      await trpc.others.changeLogo.mutate({ fileId: values.logo?.fileId });
    }
  }, []);

  const { r, values, onChange, reset } = useSettingsForm<TServerGeneralValues>({
    initialValues: INITIAL_VALUES,
    onSave,
    successMessage: t('settingsUpdated'),
    errorMessage: t('failedUpdateSettings')
  });

  useEffect(() => {
    if (!settings) return;

    reset({
      name: settings.name,
      description: settings.description ?? '',
      password: settings.password ?? '',
      onlyAskForPasswordOnFirstJoin:
        settings.onlyAskForPasswordOnFirstJoin ?? false,
      allowNewUsers: settings.allowNewUsers ?? false,
      directMessagesEnabled: settings.directMessagesEnabled ?? true,
      enablePlugins: settings.enablePlugins ?? false,
      webRtcSimulcastEnabled: settings.webRtcSimulcastEnabled ?? false,
      enableSearch: settings.enableSearch ?? true,
      showWelcomeDialog: settings.showWelcomeDialog ?? true,
      pushShowMessageContent: settings.pushShowMessageContent ?? true,
      linkPreviewsPrivateNetwork: settings.linkPreviewsPrivateNetwork ?? false,
      reportEmail: settings.reportEmail ?? '',
      klipyApiKey: settings.klipyApiKey ?? '',
      freesoundApiKey: settings.freesoundApiKey ?? '',
      afkChannelId:
        settings.afkChannelId === null
          ? AFK_OFF
          : String(settings.afkChannelId),
      afkTimeoutSeconds: String(settings.afkTimeoutSeconds)
    });
  }, [settings, reset]);

  const channels = useChannels();
  const voiceChannels = useMemo(
    () =>
      channels.filter(
        (channel) => channel.type === ChannelType.VOICE && !channel.isDm
      ),
    [channels]
  );

  const handleAfkChannelChange = useCallback(
    (value: string) => onChange('afkChannelId', value),
    [onChange]
  );

  const handleAfkTimeoutChange = useCallback(
    (value: string) => onChange('afkTimeoutSeconds', value),
    [onChange]
  );

  const handleLogoChange = useCallback(
    (picked: TPickedImage | null) => onChange('logo', picked),
    [onChange]
  );
  const handlePasswordOnFirstJoinChange = useCallback(
    (checked: boolean) => onChange('onlyAskForPasswordOnFirstJoin', checked),
    [onChange]
  );
  const handleAllowNewUsersChange = useCallback(
    (checked: boolean) => onChange('allowNewUsers', checked),
    [onChange]
  );
  const handleEnablePluginsChange = useCallback(
    (checked: boolean) => onChange('enablePlugins', checked),
    [onChange]
  );
  const handleSimulcastChange = useCallback(
    (checked: boolean) => onChange('webRtcSimulcastEnabled', checked),
    [onChange]
  );
  const handleDirectMessagesChange = useCallback(
    (checked: boolean) => onChange('directMessagesEnabled', checked),
    [onChange]
  );
  const handleSearchChange = useCallback(
    (checked: boolean) => onChange('enableSearch', checked),
    [onChange]
  );
  const handleWelcomeDialogChange = useCallback(
    (checked: boolean) => onChange('showWelcomeDialog', checked),
    [onChange]
  );
  const handlePushContentChange = useCallback(
    (checked: boolean) => onChange('pushShowMessageContent', checked),
    [onChange]
  );
  const handlePrivatePreviewsChange = useCallback(
    (checked: boolean) => onChange('linkPreviewsPrivateNetwork', checked),
    [onChange]
  );

  if (loading) {
    return <LoadingCard className="h-[600px]" />;
  }

  return (
    <SettingsSection
      title={t('serverInfoTitle')}
      description={t('serverInfoDesc')}
    >
      <Group label={t('nameLabel')}>
        <Input placeholder={t('namePlaceholder')} {...r('name')} />
      </Group>

      <Group label={t('descriptionLabel')}>
        <Textarea
          rows={4}
          placeholder={t('descriptionPlaceholder')}
          {...r('description')}
        />
      </Group>

      <Group label={t('serverPasswordLabel')}>
        <Input
          placeholder={t('serverPasswordPlaceholder')}
          {...r('password', 'password')}
        />
      </Group>

      <Group
        label={t('onlyAskForPasswordOnFirstJoinLabel')}
        description={t('onlyAskForPasswordOnFirstJoinDesc')}
      >
        <Switch
          checked={values.onlyAskForPasswordOnFirstJoin}
          onCheckedChange={handlePasswordOnFirstJoinChange}
        />
      </Group>

      <ImagePicker
        label={t('logoLabel')}
        description={t('logoDesc')}
        className="h-24 w-80 object-scale-down"
        currentUrl={getFileUrl(settings?.logo)}
        draft={values.logo}
        onChange={handleLogoChange}
      />

      <Group
        label={t('allowNewUsersLabel')}
        description={t('allowNewUsersDesc')}
      >
        <Switch
          checked={values.allowNewUsers}
          onCheckedChange={handleAllowNewUsersChange}
        />
      </Group>

      <Group label={t('pluginsLabel')} description={t('pluginsDesc')}>
        <Switch
          checked={values.enablePlugins}
          onCheckedChange={handleEnablePluginsChange}
        />
      </Group>

      <Group label={t('simulcastLabel')} description={t('simulcastDesc')}>
        <Switch
          checked={values.webRtcSimulcastEnabled}
          onCheckedChange={handleSimulcastChange}
        />
      </Group>

      <Group
        label={t('directMessagesEnabledLabel')}
        description={t('directMessagesEnabledDesc')}
      >
        <Switch
          checked={values.directMessagesEnabled}
          onCheckedChange={handleDirectMessagesChange}
        />
      </Group>

      <Group
        label={t('searchEnabledLabel')}
        description={t('searchEnabledDesc')}
      >
        <Switch
          checked={values.enableSearch}
          onCheckedChange={handleSearchChange}
        />
      </Group>

      <Group
        label={t('showWelcomeDialogLabel')}
        description={t('showWelcomeDialogDesc')}
      >
        <Switch
          checked={values.showWelcomeDialog}
          onCheckedChange={handleWelcomeDialogChange}
        />
      </Group>

      <Group label={t('afkChannelLabel')} description={t('afkChannelDesc')}>
        <Select
          value={values.afkChannelId}
          onValueChange={handleAfkChannelChange}
        >
          <SelectTrigger className="w-64">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectGroup>
              <SelectItem value={AFK_OFF}>{t('afkChannelNone')}</SelectItem>
              {voiceChannels.map((channel) => (
                <SelectItem key={channel.id} value={String(channel.id)}>
                  {channel.name}
                </SelectItem>
              ))}
            </SelectGroup>
          </SelectContent>
        </Select>
      </Group>

      <Group label={t('afkTimeoutLabel')}>
        <Select
          value={values.afkTimeoutSeconds}
          onValueChange={handleAfkTimeoutChange}
          disabled={values.afkChannelId === AFK_OFF}
        >
          <SelectTrigger className="w-64">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectGroup>
              {AFK_TIMEOUT_OPTIONS_SECONDS.map((seconds) => (
                <SelectItem key={seconds} value={String(seconds)}>
                  {t('afkTimeoutMinutes', { count: seconds / 60 })}
                </SelectItem>
              ))}
            </SelectGroup>
          </SelectContent>
        </Select>
      </Group>

      <Group label={t('reportEmailLabel')} description={t('reportEmailDesc')}>
        <Input
          {...r('reportEmail')}
          type="email"
          placeholder={t('reportEmailPlaceholder')}
        />
      </Group>

      <Group label={t('klipyApiKeyLabel')} description={t('klipyApiKeyDesc')}>
        <Input
          {...r('klipyApiKey')}
          type="password"
          autoComplete="off"
          placeholder={t('klipyApiKeyPlaceholder')}
        />
      </Group>

      <Group
        label={t('freesoundApiKeyLabel')}
        description={t('freesoundApiKeyDesc')}
      >
        <Input
          {...r('freesoundApiKey')}
          type="password"
          autoComplete="off"
          placeholder={t('freesoundApiKeyPlaceholder')}
        />
      </Group>

      <Group
        label={t('pushShowMessageContentLabel')}
        description={t('pushShowMessageContentDesc')}
      >
        <Switch
          checked={values.pushShowMessageContent}
          onCheckedChange={handlePushContentChange}
        />
      </Group>

      <Group
        label={t('linkPreviewsPrivateNetworkLabel')}
        description={t('linkPreviewsPrivateNetworkDesc')}
      >
        <Switch
          checked={values.linkPreviewsPrivateNetwork}
          onCheckedChange={handlePrivatePreviewsChange}
        />
      </Group>
    </SettingsSection>
  );
});

export { General };
