import { useSelectedDmChannelId } from '@/features/app/hooks';
import { useSelectedChannelId } from '@/features/server/channels/hooks';
import { useDmsOpen } from '@/features/server/hooks';
import { getUrlFromServer } from '@/helpers/get-file-url';
import { IOS_APP_URL, isIosDevice } from '@/helpers/ios-app';
import {
  getLocalStorageItemBool,
  LocalStorageKey,
  setLocalStorageItemBool
} from '@/helpers/storage';
import { Button, IconButton } from '@sharkord/ui';
import { Smartphone, X } from 'lucide-react';
import { memo, useCallback, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';

// on an iphone or ipad the web app keeps pointing to the app until it is hidden in that browser
const AppBanner = memo(() => {
  const { t } = useTranslation();
  const selectedChannelId = useSelectedChannelId();
  const selectedDmChannelId = useSelectedDmChannelId();
  const dmsOpen = useDmsOpen();
  const [isDismissed, setIsDismissed] = useState(() =>
    getLocalStorageItemBool(LocalStorageKey.APP_BANNER_DISMISSED)
  );

  let channelId = selectedChannelId;

  if (dmsOpen) {
    channelId = selectedDmChannelId;
  }

  // the link the app copies for a channel, which opens it there on a server it is signed in to
  const openLink = useMemo(() => {
    if (!channelId) {
      return undefined;
    }

    return `sharkord://channel?server=${encodeURIComponent(getUrlFromServer())}&channel=${channelId}`;
  }, [channelId]);

  const onDismiss = useCallback(() => {
    setLocalStorageItemBool(LocalStorageKey.APP_BANNER_DISMISSED, true);
    setIsDismissed(true);
  }, []);

  if (!isIosDevice || isDismissed) {
    return null;
  }

  return (
    <div className="flex items-center gap-2 border-b border-border bg-card px-3 py-2 text-sm">
      <Smartphone className="size-4 shrink-0 text-muted-foreground" />
      <span className="flex-1 min-w-0 truncate">{t('appBannerTitle')}</span>
      {openLink && (
        <Button size="sm" variant="outline" asChild>
          <a href={openLink}>{t('appBannerOpen')}</a>
        </Button>
      )}
      <Button size="sm" asChild>
        <a href={IOS_APP_URL} target="_blank" rel="noopener noreferrer">
          {t('appBannerGet')}
        </a>
      </Button>
      <IconButton
        icon={X}
        variant="ghost"
        size="sm"
        onClick={onDismiss}
        aria-label={t('appBannerHide')}
      />
    </div>
  );
});

export { AppBanner };
