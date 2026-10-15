import { Dialog } from '@/components/dialogs/dialogs';
import { openDialog, requestConfirmation } from '@/features/dialogs/actions';
import { useChannelById } from '@/features/server/channels/hooks';
import { useCan, usePublicServerSettings } from '@/features/server/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { getTrpcError, Permission } from '@sharkord/shared';
import { IconButton } from '@sharkord/ui';
import { BadgeCheck } from 'lucide-react';
import { memo, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TRulesButtonProps = {
  messageId: number;
  channelId: number;
};

// makes a message the new member lounge's rules, or stops it being them
const RulesButton = memo(({ messageId, channelId }: TRulesButtonProps) => {
  const { t } = useTranslation();
  const can = useCan();
  const channel = useChannelById(channelId);
  const settings = usePublicServerSettings();

  const isRules = settings?.onboardingMessageId === messageId;

  const onClick = useCallback(async () => {
    if (!isRules) {
      openDialog(Dialog.RULES_SETUP, { messageId });

      return;
    }

    const choice = await requestConfirmation({
      title: t('stopUsingAsRules'),
      message: t('stopUsingAsRulesMsg'),
      confirmLabel: t('stopUsingAsRules'),
      cancelLabel: t('cancel')
    });

    if (!choice) {
      return;
    }

    try {
      const trpc = getTRPCClient();

      await trpc.others.setOnboarding.mutate({ messageId: null, roleId: null });
    } catch (error) {
      toast.error(getTrpcError(error, t('failedSetRules')));
    }
  }, [isRules, messageId, t]);

  if (!can(Permission.MANAGE_SETTINGS) || !channel || channel.isDm) {
    return null;
  }

  return (
    <IconButton
      size="sm"
      variant="ghost"
      icon={BadgeCheck}
      onClick={onClick}
      title={isRules ? t('stopUsingAsRules') : t('useAsRules')}
    />
  );
});

export { RulesButton };
