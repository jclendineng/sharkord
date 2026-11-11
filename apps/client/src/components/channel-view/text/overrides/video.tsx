import { memo } from 'react';
import { useTranslation } from 'react-i18next';
import { OverrideLayout } from './layout';
import { LinkOverride } from './link';
import { VideoPlayer } from './video-player';

type TVideoOverrideProps = {
  src: string;
};

const VideoOverride = memo(({ src }: TVideoOverrideProps) => {
  const { t } = useTranslation('common');
  return (
    <OverrideLayout>
      <VideoPlayer url={src} className="max-h-75" />
      <LinkOverride link={src} label={t('openInNewTab')} />
    </OverrideLayout>
  );
});

export { VideoOverride };
