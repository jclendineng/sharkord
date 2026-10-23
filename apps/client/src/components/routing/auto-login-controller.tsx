import { setIsAutoConnecting } from '@/features/app/actions';
import { useIsAppLoading, useIsPluginsLoading } from '@/features/app/hooks';
import {
  clearServerSnapshot,
  connect,
  isAuthFailure,
  resetServerState,
  restoreServerSnapshot,
  saveServerSnapshot,
  setDisconnectInfo
} from '@/features/server/actions';
import {
  useDisconnectInfo,
  useIsConnected,
  useIsReconnecting
} from '@/features/server/hooks';
import {
  getLocalStorageItem,
  getLocalStorageItemBool,
  getSessionStorageItem,
  LocalStorageKey,
  removeLocalStorageItem,
  removeSessionStorageItem,
  SessionStorageKey,
  setLocalStorageItemBool,
  setSessionStorageItem
} from '@/helpers/storage';
import { memo, useEffect, useRef } from 'react';

const AutoLoginController = memo(() => {
  const isConnected = useIsConnected();
  const isAppLoading = useIsAppLoading();
  const isPluginsLoading = useIsPluginsLoading();
  const disconnectInfo = useDisconnectInfo();
  const isReconnecting = useIsReconnecting();
  const autoLoginAttempted = useRef(false);

  useEffect(() => {
    if (
      isAppLoading ||
      isPluginsLoading ||
      isConnected ||
      isReconnecting ||
      disconnectInfo ||
      autoLoginAttempted.current
    ) {
      // ignore if the app is not done loading, if we're already connected or in the process of
      // connecting. a dropped connection is reconnectToServer's to recover: a second connect
      // here would handshake on the same socket, one join would fail on the replaced hash, and
      // that failure signed the tab out the next time the connection dropped
      return;
    }

    const autoLoginEnabled = getLocalStorageItemBool(
      LocalStorageKey.AUTO_LOGIN
    );

    // a refresh: the tab still holds the session it signed in with, kept whether or not login
    // automatically is on, which only decides whether a new tab or browser stays signed in
    let token = getSessionStorageItem(SessionStorageKey.TOKEN);
    // the server as it was before the refresh, shown while joining runs instead of a loading
    // screen. only on a refresh, a new tab has no copy of its own
    const restored = !!token && restoreServerSnapshot();

    if (!token && autoLoginEnabled) {
      token = getLocalStorageItem(LocalStorageKey.AUTO_LOGIN_TOKEN);
    }

    if (!token) {
      return;
    }

    autoLoginAttempted.current = true;

    setIsAutoConnecting(true);
    setSessionStorageItem(SessionStorageKey.TOKEN, token);

    connect()
      .catch((error) => {
        if (restored) {
          resetServerState();
        }

        clearServerSnapshot();

        // a few quick refreshes can run into a rate limit, which used to sign people out
        if (!isAuthFailure(error)) {
          setDisconnectInfo({
            code: 0,
            reason: '',
            wasClean: false,
            time: new Date()
          });

          return;
        }

        // token expired or invalid clear auto-login state so the user
        // sees the connect screen and can log in manually
        removeLocalStorageItem(LocalStorageKey.AUTO_LOGIN_TOKEN);
        removeSessionStorageItem(SessionStorageKey.TOKEN);
        setLocalStorageItemBool(LocalStorageKey.AUTO_LOGIN, false);
      })
      .finally(() => {
        // reset auto-login attempt state so if the user logs out and back in they can try auto-login again
        autoLoginAttempted.current = false;
        setIsAutoConnecting(false);
      });
  }, [
    isAppLoading,
    isPluginsLoading,
    isConnected,
    isReconnecting,
    disconnectInfo
  ]);

  useEffect(() => {
    window.addEventListener('pagehide', saveServerSnapshot);

    return () => {
      window.removeEventListener('pagehide', saveServerSnapshot);
    };
  }, []);

  return null;
});

export { AutoLoginController };
