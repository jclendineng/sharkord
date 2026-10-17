import { getUrlFromServer } from '@/helpers/get-file-url';
import {
  Alert,
  AlertDescription,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Group,
  Input
} from '@sharkord/ui';
import { memo, useCallback, useState, type FormEvent } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TResetPasswordProps = {
  token: string;
  onDone: () => void;
};

// the page a moderator's reset link opens, there being no email to send one through
const ResetPassword = memo(({ token, onDone }: TResetPasswordProps) => {
  const { t } = useTranslation('connect');
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [error, setError] = useState<string>();
  const [saving, setSaving] = useState(false);

  const onPasswordChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setPassword(event.target.value);
    },
    []
  );

  const onConfirmationChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setConfirmation(event.target.value);
    },
    []
  );

  const onSubmit = useCallback(
    async (event: FormEvent) => {
      event.preventDefault();

      if (password !== confirmation) {
        setError(t('resetPasswordMismatch'));
        return;
      }

      setSaving(true);
      setError(undefined);

      try {
        const response = await fetch(`${getUrlFromServer()}/password-reset`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ token, password })
        });

        if (!response.ok) {
          const data = (await response.json()) as {
            errors?: Record<string, string>;
          };

          setError(
            data.errors?.token ??
              data.errors?.password ??
              t('resetPasswordFailed')
          );
          return;
        }

        toast.success(t('resetPasswordDone'));
        onDone();
      } catch {
        setError(t('resetPasswordFailed'));
      } finally {
        setSaving(false);
      }
    },
    [password, confirmation, token, onDone, t]
  );

  return (
    <div className="flex flex-col gap-2 justify-center items-center min-h-svh px-4 py-6">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-center">
            {t('resetPasswordTitle')}
          </CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={onSubmit} className="flex flex-col gap-4">
            <Group label={t('resetPasswordNew')}>
              <Input
                type="password"
                value={password}
                onChange={onPasswordChange}
                autoComplete="new-password"
                minLength={4}
              />
            </Group>
            <Group label={t('resetPasswordConfirm')}>
              <Input
                type="password"
                value={confirmation}
                onChange={onConfirmationChange}
                autoComplete="new-password"
                minLength={4}
              />
            </Group>
            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}
            <Button type="submit" disabled={saving || password.length < 4}>
              {t('resetPasswordBtn')}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
});

export { ResetPassword };
