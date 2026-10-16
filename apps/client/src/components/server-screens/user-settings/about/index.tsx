import { SettingsSection } from '@/components/server-screens/settings-shell/section';
import { useInfo } from '@/features/server/hooks';
import { Group } from '@sharkord/ui';
import { memo } from 'react';
import { useTranslation } from 'react-i18next';

const SOURCE_URL = 'https://github.com/jclendineng/sharkord';

const About = memo(() => {
  const { t } = useTranslation('settings');
  const info = useInfo();

  return (
    <SettingsSection title={t('aboutTitle')} description={t('aboutDesc')}>
      <Group label={t('aboutVersionLabel')}>
        <span className="text-sm">v{VITE_APP_VERSION}</span>
      </Group>

      {info?.name && (
        <Group label={t('aboutServerLabel')}>
          <span className="text-sm">{info.name}</span>
        </Group>
      )}

      {info?.reportEmail && (
        <Group
          label={t('aboutContactLabel')}
          description={t('aboutContactDesc')}
        >
          <a
            className="text-sm text-primary underline"
            href={`mailto:${info.reportEmail}`}
          >
            {info.reportEmail}
          </a>
        </Group>
      )}

      <Group label={t('aboutSourceLabel')}>
        <div className="flex gap-4 text-sm">
          <a
            className="text-primary underline"
            href={SOURCE_URL}
            target="_blank"
            rel="noopener noreferrer"
          >
            {t('aboutSourceLink')}
          </a>
          <a
            className="text-primary underline"
            href={`${SOURCE_URL}/issues`}
            target="_blank"
            rel="noopener noreferrer"
          >
            {t('aboutReportProblem')}
          </a>
        </div>
      </Group>
    </SettingsSection>
  );
});

export { About };
