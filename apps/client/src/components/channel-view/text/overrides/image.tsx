import { FullScreenImage } from '@/components/fullscreen-image/content';
import { cn } from '@/lib/utils';
import { Skeleton } from '@sharkord/ui';
import { memo, useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { OverrideLayout } from './layout';
import { LinkOverride } from './link';

type TImageOverrideProps = {
  src: string;
  alt?: string;
  title?: string;
};

// the picture stays mounted while it loads, invisible, with a placeholder where it will be.
// swapping one for the other never loaded the picture, so the placeholder was switched off and
// a message of pictures showed as blank space until they arrived
const ImageOverride = memo(({ src, alt }: TImageOverrideProps) => {
  const { t } = useTranslation('common');
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState(false);

  const onLoad = useCallback(() => {
    setLoaded(true);
  }, []);

  const onError = useCallback(() => {
    setError(true);
  }, []);

  if (error) return null;

  return (
    <OverrideLayout>
      {!loaded && <Skeleton className="w-75 h-75 rounded-lg" />}

      <FullScreenImage
        src={src}
        alt={alt}
        onLoad={onLoad}
        onError={onError}
        className={cn(
          'max-w-full max-h-75 object-contain object-left w-fit rounded-lg',
          !loaded && 'absolute size-px opacity-0'
        )}
        crossOrigin="anonymous"
      />

      <LinkOverride link={src} label={t('openInNewTab')} />
    </OverrideLayout>
  );
});

export { ImageOverride };
