import { LanguageSwitcher } from '@/components/language-switcher';
import { PluginSlotRenderer } from '@/components/plugin-slot-renderer';
import { connect } from '@/features/server/actions';
import { useInfo } from '@/features/server/hooks';
import { getFileUrl, getUrlFromServer } from '@/helpers/get-file-url';
import {
  getLocalStorageItem,
  getLocalStorageItemBool,
  LocalStorageKey,
  removeLocalStorageItem,
  SessionStorageKey,
  setLocalStorageItem,
  setLocalStorageItemBool,
  setSessionStorageItem
} from '@/helpers/storage';
import { useForm } from '@/hooks/use-form';
import { PluginSlot, TestId, TOTP_REQUIRED_MESSAGE } from '@sharkord/shared';
import {
  Alert,
  AlertDescription,
  AlertTitle,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Group,
  Input,
  Label,
  Separator,
  Spinner,
  Switch
} from '@sharkord/ui';
import {
  memo,
  useCallback,
  useEffect,
  useMemo,
  useState,
  type FormEvent
} from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import { useOidcLogin } from './hooks/use-oidc-login';
import { useOverflowsScreen } from './hooks/use-overflows-screen';
import { ResetPassword } from './reset-password';

const Connect = memo(() => {
  const { t } = useTranslation('connect');
  const { values, r, setErrors, onChange } = useForm<{
    identity: string;
    password: string;
    totp: string;
    autoLogin: boolean;
  }>({
    identity: getLocalStorageItem(LocalStorageKey.IDENTITY) || '',
    password: '',
    totp: '',
    // on unless turned off: a refresh should not sign anyone out, and a session lasts until
    // signing out or its expiry
    autoLogin: getLocalStorageItemBool(LocalStorageKey.AUTO_LOGIN, true)
  });
  // the password was right and the account has two-factor on, so the code field shows
  const [needsCode, setNeedsCode] = useState(false);

  const [loading, setLoading] = useState(false);
  const [resetToken, setResetToken] = useState(() =>
    new URLSearchParams(window.location.search).get('reset')
  );

  // the link's token leaves the address bar once used, so a reload shows the sign in again
  const clearResetToken = useCallback(() => {
    const url = new URL(window.location.href);

    url.searchParams.delete('reset');
    window.history.replaceState(null, '', url.toString());
    setResetToken(null);
  }, []);
  const info = useInfo();

  // an iphone, ipad or mac, where the app can take the invite over from the browser
  const appInviteLink = useMemo(() => {
    const isApple = /iPhone|iPad|iPod|Macintosh/.test(navigator.userAgent);
    const invite = new URLSearchParams(window.location.search).get('invite');

    if (!isApple || !invite) {
      return undefined;
    }

    // with the subpath a server behind a proxy is served under, which the origin alone leaves out
    return `sharkord://join?server=${encodeURIComponent(getUrlFromServer())}&invite=${encodeURIComponent(invite)}`;
  }, []);

  const inviteCode = useMemo(() => {
    const urlParams = new URLSearchParams(window.location.search);
    const invite = urlParams.get('invite');
    return invite || undefined;
  }, []);

  const startSession = useCallback(
    async (token: string) => {
      setSessionStorageItem(SessionStorageKey.TOKEN, token);
      setLocalStorageItemBool(LocalStorageKey.AUTO_LOGIN, values.autoLogin);

      if (values.autoLogin) {
        setLocalStorageItem(LocalStorageKey.AUTO_LOGIN_TOKEN, token);
      } else {
        removeLocalStorageItem(LocalStorageKey.AUTO_LOGIN_TOKEN);
      }

      await connect();
    },
    [values.autoLogin]
  );

  const oidc = useOidcLogin({ onToken: startSession });

  const onConnectClick = useCallback(async () => {
    setLoading(true);

    try {
      const url = getUrlFromServer();
      const response = await fetch(`${url}/login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          identity: values.identity,
          password: values.password,
          invite: inviteCode,
          totp: needsCode ? values.totp : undefined
        })
      });

      if (!response.ok) {
        const data = (await response.json()) as {
          errors?: Record<string, string>;
        };
        const errors = data.errors ?? {};

        if (errors.totp) {
          setNeedsCode(true);
        }

        // being asked for the code is the next step, not a mistake to show in red
        if (errors.totp === TOTP_REQUIRED_MESSAGE) {
          delete errors.totp;
        }

        setErrors(errors);
        return;
      }

      const data = (await response.json()) as { token: string };

      setLocalStorageItem(LocalStorageKey.IDENTITY, values.identity);

      await startSession(data.token);
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);

      toast.error(t('connectError', { message: errorMessage }));
    } finally {
      setLoading(false);
    }
  }, [
    values.identity,
    values.password,
    values.totp,
    needsCode,
    setErrors,
    inviteCode,
    startSession,
    t
  ]);

  const onFormSubmit = useCallback(
    (event: FormEvent<HTMLFormElement>) => {
      event.preventDefault();
      onConnectClick();
    },
    [onConnectClick]
  );

  const onAutoLoginToggle = useCallback(() => {
    const nextAutoLogin = !values.autoLogin;

    onChange('autoLogin', nextAutoLogin);
    setLocalStorageItemBool(LocalStorageKey.AUTO_LOGIN, nextAutoLogin);

    if (!nextAutoLogin) {
      removeLocalStorageItem(LocalStorageKey.AUTO_LOGIN_TOKEN);
    }
  }, [onChange, values.autoLogin]);

  const logoSrc = useMemo(() => {
    if (info?.logo) {
      return getFileUrl(info.logo);
    }

    return './logo.webp';
  }, [info]);

  const inviteAlert = useMemo(
    () => (
      <Alert variant="info">
        <AlertTitle>{t('invitedTitle')}</AlertTitle>
        <AlertDescription>
          <span>{t('invitedHowTo')}</span>
          <span className="font-mono text-xs">
            {t('inviteCode', { code: inviteCode })}
          </span>
        </AlertDescription>
      </Alert>
    ),
    [t, inviteCode]
  );

  const { contentRef, overflows } = useOverflowsScreen();

  // the page itself scrolls here, not a box inside it: safari only runs a page under its glass
  // toolbar when the document scrolls, and an invite makes the card taller than a phone
  useEffect(() => {
    document.documentElement.classList.add('document-scroll');

    return () => {
      document.documentElement.classList.remove('document-scroll');
    };
  }, []);

  if (resetToken) {
    return <ResetPassword token={resetToken} onDone={clearResetToken} />;
  }

  if (oidc.isCompleting) {
    return (
      <div className="flex flex-col justify-center items-center min-h-svh gap-2">
        <Spinner size="lg" />
        <span className="text-xl">{t('oidcCompleting')}</span>
      </div>
    );
  }

  // a page a little taller than the screen stutters in safari: scrolling tucks the toolbar
  // away, the screen grows past the end of the page, the page snaps back and the toolbar
  // returns. one that overflows at all gets a toolbar's height more, so it keeps scrolling
  let pageClassName = 'flex flex-col justify-center items-center min-h-svh';

  if (overflows) {
    pageClassName = 'flex flex-col items-center min-h-[calc(200lvh-100svh)]';
  }

  return (
    <div className="relative">
      <div className="hidden md:block fixed bottom-6 right-6 z-50">
        <LanguageSwitcher variant="icon" />
      </div>
      <div className={pageClassName}>
        <div
          ref={contentRef}
          className="flex flex-col gap-2 items-center w-full px-4 py-6"
        >
          <Card className="w-full max-w-sm shrink-0">
            <CardHeader>
              <CardTitle className="flex flex-col items-center gap-2 text-center">
                <img
                  src={logoSrc}
                  alt="Sharkord"
                  className="block max-h-32 max-w-full rounded-[5px]"
                />
                {info?.name && (
                  <span className="text-xl font-bold leading-tight">
                    {info.name}
                  </span>
                )}
              </CardTitle>
              <PluginSlotRenderer slotId={PluginSlot.CONNECT_SCREEN} />
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
              {info?.description && (
                <span className="text-sm text-muted-foreground">
                  {info?.description}
                </span>
              )}

              {appInviteLink && (
                <div className="flex flex-col gap-2">
                  {inviteAlert}
                  <Button asChild>
                    <a href={appInviteLink}>{t('openInApp')}</a>
                  </Button>
                  <div className="flex items-center gap-2 text-xs text-muted-foreground">
                    <Separator className="w-auto flex-1" />
                    {t('continueInBrowser')}
                    <Separator className="w-auto flex-1" />
                  </div>
                </div>
              )}

              {oidc.isLocalLoginAllowed && (
                <form
                  className="flex flex-col gap-2"
                  onSubmit={onFormSubmit}
                  data-testid={TestId.CONNECT_FORM}
                >
                  <Group label={t('identityLabel')} help={t('identityHelp')}>
                    <Input
                      {...r('identity')}
                      autoComplete="username"
                      data-testid={TestId.CONNECT_IDENTITY_INPUT}
                    />
                  </Group>
                  <Group label={t('passwordLabel')}>
                    <Input
                      {...r('password')}
                      type="password"
                      autoComplete="current-password"
                      onEnter={onConnectClick}
                      data-testid={TestId.CONNECT_PASSWORD_INPUT}
                    />
                  </Group>
                  {needsCode && (
                    <Group label={t('totpLabel')} help={t('totpHelp')}>
                      <Input
                        {...r('totp')}
                        autoComplete="one-time-code"
                        inputMode="numeric"
                        autoFocus
                        onEnter={onConnectClick}
                      />
                    </Group>
                  )}
                </form>
              )}

              <div
                className="flex items-center gap-2 w-fit cursor-pointer"
                data-testid={TestId.CONNECT_AUTO_LOGIN_SWITCH}
                onClick={onAutoLoginToggle}
              >
                <Switch checked={values.autoLogin} />
                <Label className="text-sm cursor-pointer">
                  {t('autoLoginLabel')}
                </Label>
              </div>

              <div className="flex flex-col gap-2">
                {!window.isSecureContext && (
                  <Alert variant="destructive">
                    <AlertTitle>{t('insecureTitle')}</AlertTitle>
                    <AlertDescription>{t('insecureDesc')}</AlertDescription>
                  </Alert>
                )}

                {oidc.isLocalLoginAllowed && (
                  <Button
                    className="w-full"
                    variant="outline"
                    onClick={onConnectClick}
                    disabled={loading || !values.identity || !values.password}
                    data-testid={TestId.CONNECT_BUTTON}
                  >
                    {t('connectBtn')}
                  </Button>
                )}

                {oidc.isEnabled && (
                  <Button
                    className="w-full"
                    variant="secondary"
                    onClick={oidc.startLogin}
                    disabled={loading}
                    data-testid={TestId.CONNECT_OIDC_BUTTON}
                  >
                    {t('oidcBtn')}
                  </Button>
                )}

                {oidc.isLocalLoginAllowed &&
                  !info?.allowNewUsers &&
                  !inviteCode && (
                    <span className="text-xs text-muted-foreground text-center">
                      {t('registrationDisabled')}
                    </span>
                  )}

                {inviteCode && !appInviteLink && inviteAlert}
              </div>
            </CardContent>
          </Card>

          <div className="flex justify-center items-center gap-2 text-xs text-muted-foreground select-none">
            <span>v{VITE_APP_VERSION}</span>
            <a
              href="https://github.com/jclendineng/sharkord"
              target="_blank"
              rel="noopener noreferrer"
            >
              GitHub
            </a>

            <a
              className="text-xs"
              href="https://sharkord.com"
              target="_blank"
              rel="noopener noreferrer"
            >
              Sharkord
            </a>
          </div>
          <div className="md:hidden">
            <LanguageSwitcher variant="icon" />
          </div>
        </div>
      </div>
    </div>
  );
});

export { Connect };
