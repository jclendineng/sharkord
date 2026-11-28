import { SettingsSection } from '@/components/server-screens/settings-shell/section';
import { useSettingsForm } from '@/components/server-screens/settings-shell/use-settings-form';
import {
  setBrowserNotifications,
  setBrowserNotificationsForDms,
  setBrowserNotificationsForMentions,
  setBrowserNotificationsForReplies,
  setMessageSentSound,
  setNotificationSounds
} from '@/features/app/actions';
import {
  useBrowserNotifications,
  useBrowserNotificationsForDms,
  useBrowserNotificationsForMentions,
  useBrowserNotificationsForReplies,
  useMessageSentSound,
  useNotificationSounds
} from '@/features/app/hooks';
import {
  Group,
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Switch
} from '@sharkord/ui';
import { memo, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import {
  fromMessageLevel,
  toMessageLevel,
  type TMessageLevel
} from './helpers';

type TNotificationsValues = {
  level: TMessageLevel;
  dms: boolean;
  replies: boolean;
  sounds: boolean;
  sentSound: boolean;
};

const Notifications = memo(() => {
  const { t } = useTranslation('settings');
  const all = useBrowserNotifications();
  const mentions = useBrowserNotificationsForMentions();
  const dms = useBrowserNotificationsForDms();
  const replies = useBrowserNotificationsForReplies();
  const sounds = useNotificationSounds();
  const sentSound = useMessageSentSound();

  const onSave = useCallback(async (values: TNotificationsValues) => {
    const flags = fromMessageLevel(values.level);

    setBrowserNotifications(flags.all);
    setBrowserNotificationsForMentions(flags.mentions);
    setBrowserNotificationsForDms(values.dms);
    setBrowserNotificationsForReplies(values.replies);
    setNotificationSounds(values.sounds);
    setMessageSentSound(values.sentSound);
  }, []);

  const level = toMessageLevel(all, mentions);

  const { values, onChange } = useSettingsForm<TNotificationsValues>({
    initialValues: { level, dms, replies, sounds, sentSound },
    onSave,
    successMessage: t('notificationsUpdated'),
    errorMessage: t('failedUpdateNotifications')
  });

  const handleLevelChange = useCallback(
    (value: string) => onChange('level', value as TMessageLevel),
    [onChange]
  );
  const handleDmsChange = useCallback(
    (value: boolean) => onChange('dms', value),
    [onChange]
  );
  const handleRepliesChange = useCallback(
    (value: boolean) => onChange('replies', value),
    [onChange]
  );
  const handleSoundsChange = useCallback(
    (value: boolean) => onChange('sounds', value),
    [onChange]
  );
  const handleSentSoundChange = useCallback(
    (value: boolean) => onChange('sentSound', value),
    [onChange]
  );

  return (
    <SettingsSection
      title={t('notificationsTitle')}
      description={t('notificationsDesc')}
    >
      <Group label={t('messageLevelLabel')} description={t('messageLevelDesc')}>
        <Select value={values.level} onValueChange={handleLevelChange}>
          <SelectTrigger className="w-64">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectGroup>
              <SelectItem value="all">{t('messageLevelAll')}</SelectItem>
              <SelectItem value="mentions">
                {t('messageLevelMentions')}
              </SelectItem>
              <SelectItem value="off">{t('messageLevelOff')}</SelectItem>
            </SelectGroup>
          </SelectContent>
        </Select>
      </Group>
      <Group
        label={t('dmNotificationsLabel')}
        description={t('dmNotificationsDesc')}
        inline
      >
        <Switch checked={values.dms} onCheckedChange={handleDmsChange} />
      </Group>
      <Group
        label={t('repliesNotificationsLabel')}
        description={t('repliesNotificationsDesc')}
        inline
      >
        <Switch
          checked={values.replies || values.level === 'all'}
          disabled={values.level === 'all'}
          onCheckedChange={handleRepliesChange}
        />
      </Group>
      <Group label={t('soundsLabel')} description={t('soundsDesc')} inline>
        <Switch checked={values.sounds} onCheckedChange={handleSoundsChange} />
      </Group>
      <Group
        label={t('messageSentSoundLabel')}
        description={t('messageSentSoundDesc')}
        inline
      >
        <Switch
          checked={values.sentSound}
          disabled={!values.sounds}
          onCheckedChange={handleSentSoundChange}
        />
      </Group>
    </SettingsSection>
  );
});

export { Notifications };
