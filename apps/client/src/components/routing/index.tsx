import { ReconnectingOverlay } from '@/components/reconnecting-overlay';
import {
  useIsAppLoading,
  useIsAutoConnecting,
  useIsPluginsLoading
} from '@/features/app/hooks';
import {
  useDisconnectInfo,
  useIsConnected,
  useIsReconnecting,
  useIsRestoredFromSnapshot
} from '@/features/server/hooks';
import { Connect } from '@/screens/connect';
import { Disconnected } from '@/screens/disconnected';
import { LoadingApp } from '@/screens/loading-app';
import { ServerView } from '@/screens/server-view';
import { DisconnectCode } from '@sharkord/shared';
import { memo } from 'react';
import { useTranslation } from 'react-i18next';
import { useDocumentTitle } from './hooks/use-document-title';
import { useOidcAutoRedirect } from './hooks/use-oidc-auto-redirect';

const Routing = memo(() => {
  const { t } = useTranslation('connect');
  const isConnected = useIsConnected();
  const isAppLoading = useIsAppLoading();
  const isPluginsLoading = useIsPluginsLoading();
  const disconnectInfo = useDisconnectInfo();
  const isAutoConnecting = useIsAutoConnecting();
  const isReconnecting = useIsReconnecting();
  const isRestoredFromSnapshot = useIsRestoredFromSnapshot();

  useDocumentTitle();
  useOidcAutoRedirect();

  if (isAppLoading || isPluginsLoading) {
    return (
      <LoadingApp text={isAppLoading ? t('loadingApp') : t('loadingPlugins')} />
    );
  }

  if (!isConnected && !isReconnecting) {
    if (isAutoConnecting) {
      // resuming a session, which on a refresh is still the page loading rather than a sign in
      return <LoadingApp text={t('loadingApp')} />;
    }

    if (
      disconnectInfo &&
      (!disconnectInfo.wasClean ||
        disconnectInfo.code === DisconnectCode.KICKED ||
        disconnectInfo.code === DisconnectCode.BANNED ||
        disconnectInfo.code === DisconnectCode.SERVER_SHUTDOWN)
    ) {
      return <Disconnected info={disconnectInfo} />;
    }

    return <Connect />;
  }

  // mounted again once joining returns: views that fetch on mount did so with no connection
  // while the copy saved before a refresh was showing
  return (
    <>
      {isReconnecting && <ReconnectingOverlay />}

      <div className="contents" inert={isReconnecting}>
        <ServerView key={isRestoredFromSnapshot ? 'snapshot' : 'live'} />
      </div>
    </>
  );
});

export { Routing };
