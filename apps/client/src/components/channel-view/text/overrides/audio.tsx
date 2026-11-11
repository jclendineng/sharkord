import { memo } from 'react';
import { useTranslation } from 'react-i18next';
import { AudioPlayer } from './audio-player';
import { OverrideLayout } from './layout';
import { LinkOverride } from './link';

type TAudioOverrideProps = {
  src: string;
};

const AudioOverride = memo(({ src }: TAudioOverrideProps) => {
  const { t } = useTranslation('common');
  return (
    <OverrideLayout>
      <AudioPlayer url={src} />
      <LinkOverride link={src} label={t('openInNewTab')} />
    </OverrideLayout>
  );
});

export { AudioOverride };
