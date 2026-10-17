import { useRoles } from '@/features/server/roles/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { getTrpcError, OWNER_ROLE_ID } from '@sharkord/shared';
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  Group,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Switch
} from '@sharkord/ui';
import { memo, useCallback, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import type { TDialogBaseProps } from '../types';

type TRulesSetupDialogProps = TDialogBaseProps & {
  messageId: number;
};

// the new member lounge: reacting to this message gives a role, which the server's other
// channels are opened to
const RulesSetupDialog = memo(
  ({ isOpen, close, messageId }: TRulesSetupDialogProps) => {
    const { t } = useTranslation('dialogs');
    const roles = useRoles();
    const [roleId, setRoleId] = useState<string>();
    const [giveExistingMembers, setGiveExistingMembers] = useState(true);
    const [closeOtherChannels, setCloseOtherChannels] = useState(true);
    const [removeDefaultRole, setRemoveDefaultRole] = useState(true);
    const [saving, setSaving] = useState(false);

    // the owner's role and the one every member starts with would gate nothing
    const choices = useMemo(
      () =>
        roles.filter((role) => role.id !== OWNER_ROLE_ID && !role.isDefault),
      [roles]
    );

    const defaultRole = useMemo(
      () => roles.find((role) => role.isDefault),
      [roles]
    );

    const onSave = useCallback(async () => {
      if (!roleId) {
        return;
      }

      setSaving(true);

      try {
        const trpc = getTRPCClient();

        await trpc.others.setOnboarding.mutate({
          messageId,
          roleId: Number(roleId),
          giveExistingMembers,
          closeOtherChannels,
          removeDefaultRole: removeDefaultRole && !!defaultRole
        });

        close();
      } catch (error) {
        toast.error(getTrpcError(error, t('failedSetRules')));
      } finally {
        setSaving(false);
      }
    }, [
      close,
      closeOtherChannels,
      defaultRole,
      giveExistingMembers,
      messageId,
      removeDefaultRole,
      roleId,
      t
    ]);

    return (
      <Dialog open={isOpen}>
        <DialogContent onInteractOutside={close} close={close}>
          <DialogHeader>
            <DialogTitle>{t('rulesSetupTitle')}</DialogTitle>
            <DialogDescription>{t('rulesRoleHelp')}</DialogDescription>
          </DialogHeader>

          <Group label={t('rulesRoleLabel')}>
            <Select value={roleId} onValueChange={setRoleId}>
              <SelectTrigger className="w-[240px]">
                <SelectValue placeholder={t('rulesRolePlaceholder')} />
              </SelectTrigger>
              <SelectContent>
                {choices.map((role) => (
                  <SelectItem key={role.id} value={String(role.id)}>
                    {role.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Group>

          <Group
            label={t('rulesCloseOthers')}
            description={t('rulesCloseOthersHelp')}
          >
            <Switch
              checked={closeOtherChannels}
              onCheckedChange={setCloseOtherChannels}
            />
          </Group>

          {defaultRole && (
            <Group
              label={t('rulesRemoveDefault', { role: defaultRole.name })}
              description={t('rulesRemoveDefaultHelp', {
                role: defaultRole.name
              })}
            >
              <Switch
                checked={removeDefaultRole}
                onCheckedChange={setRemoveDefaultRole}
              />
            </Group>
          )}

          <Group
            label={t('rulesGiveExisting')}
            description={t('rulesGiveExistingHelp')}
          >
            <Switch
              checked={giveExistingMembers}
              onCheckedChange={setGiveExistingMembers}
            />
          </Group>

          <DialogFooter className="gap-2">
            <Button variant="ghost" onClick={close}>
              {t('cancel')}
            </Button>
            <Button onClick={onSave} disabled={!roleId || saving}>
              {t('saveChanges')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    );
  }
);

export { RulesSetupDialog };
