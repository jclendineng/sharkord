import { SettingsSection } from '@/components/server-screens/settings-shell/section';
import { useOwnUserPasswordSet } from '@/features/server/users/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { getTrpcError } from '@sharkord/shared';
import { Button, Group, Input } from '@sharkord/ui';
import { memo, useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TSetup = {
  secret: string;
  uri: string;
};

// the secret in groups of four, the way authenticator apps show a key to type in
const groupSecret = (secret: string) =>
  secret.match(/.{1,4}/g)?.join(' ') ?? secret;

const TwoFactor = memo(() => {
  const { t } = useTranslation('settings');
  const hasPassword = useOwnUserPasswordSet();
  const [enabled, setEnabled] = useState<boolean>();
  const [setup, setSetup] = useState<TSetup>();
  const [code, setCode] = useState('');
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>();
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const load = async () => {
      try {
        const trpc = getTRPCClient();
        const status = await trpc.users.getTwoFactor.query();

        setEnabled(status.enabled);
      } catch {
        setEnabled(undefined);
      }
    };

    load();
  }, []);

  const onCodeChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setCode(event.target.value);
    },
    []
  );

  const onStart = useCallback(async () => {
    setBusy(true);

    try {
      const trpc = getTRPCClient();

      setSetup(await trpc.users.startTwoFactor.mutate());
      setCode('');
    } catch (error) {
      toast.error(getTrpcError(error, t('failedTwoFactor')));
    } finally {
      setBusy(false);
    }
  }, [t]);

  const onConfirm = useCallback(async () => {
    setBusy(true);

    try {
      const trpc = getTRPCClient();
      const result = await trpc.users.confirmTwoFactor.mutate({ code });

      setRecoveryCodes(result.recoveryCodes);
      setSetup(undefined);
      setEnabled(true);
      setCode('');
    } catch (error) {
      toast.error(getTrpcError(error, t('failedTwoFactor')));
    } finally {
      setBusy(false);
    }
  }, [code, t]);

  const onDisable = useCallback(async () => {
    setBusy(true);

    try {
      const trpc = getTRPCClient();

      await trpc.users.disableTwoFactor.mutate({ code });
      setEnabled(false);
      setRecoveryCodes(undefined);
      setCode('');
      toast.success(t('twoFactorOff'));
    } catch (error) {
      toast.error(getTrpcError(error, t('failedTwoFactor')));
    } finally {
      setBusy(false);
    }
  }, [code, t]);

  if (!hasPassword || enabled === undefined) return null;

  return (
    <SettingsSection
      title={t('twoFactorTitle')}
      description={t('twoFactorDesc')}
    >
      {recoveryCodes && (
        <Group
          label={t('recoveryCodesLabel')}
          description={t('recoveryCodesDesc')}
        >
          <pre className="rounded-md bg-muted p-3 text-sm">
            {recoveryCodes.join('\n')}
          </pre>
        </Group>
      )}

      {!enabled && !setup && (
        <Button onClick={onStart} disabled={busy} className="w-fit">
          {t('twoFactorStartBtn')}
        </Button>
      )}

      {setup && (
        <>
          <Group
            label={t('twoFactorKeyLabel')}
            description={t('twoFactorKeyDesc')}
          >
            <code className="rounded-md bg-muted p-2 text-sm">
              {groupSecret(setup.secret)}
            </code>
            <a href={setup.uri} className="text-sm underline">
              {t('twoFactorOpenApp')}
            </a>
          </Group>
          <Group label={t('twoFactorCodeLabel')}>
            <Input
              value={code}
              onChange={onCodeChange}
              autoComplete="one-time-code"
              inputMode="numeric"
            />
          </Group>
          <Button
            onClick={onConfirm}
            disabled={busy || !code}
            className="w-fit"
          >
            {t('twoFactorConfirmBtn')}
          </Button>
        </>
      )}

      {enabled && (
        <>
          <Group label={t('twoFactorDisableLabel')}>
            <Input
              value={code}
              onChange={onCodeChange}
              autoComplete="one-time-code"
              placeholder={t('twoFactorDisablePlaceholder')}
            />
          </Group>
          <Button
            variant="destructive"
            onClick={onDisable}
            disabled={busy || !code}
            className="w-fit"
          >
            {t('twoFactorDisableBtn')}
          </Button>
        </>
      )}
    </SettingsSection>
  );
});

export { TwoFactor };
