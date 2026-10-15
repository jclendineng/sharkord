import { UserAvatar } from '@/components/user-avatar';
import { setSelectedDmChannelId } from '@/features/app/actions';
import { loadDirectMessages } from '@/features/server/dms/actions';
import { useFriendLists } from '@/features/server/dms/hooks';
import { useUsers } from '@/features/server/users/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { GROUP_DM_MAX_MEMBERS, getTrpcError } from '@sharkord/shared';
import {
  AutoFocus,
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  Input
} from '@sharkord/ui';
import { Check } from 'lucide-react';
import { memo, useCallback, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import type { TDialogBaseProps } from '../types';

type TFriendOptionProps = {
  userId: number;
  name: string;
  picked: boolean;
  disabled: boolean;
  onToggle: (userId: number) => void;
};

const FriendOption = memo(
  ({ userId, name, picked, disabled, onToggle }: TFriendOptionProps) => {
    const onClick = useCallback(() => onToggle(userId), [onToggle, userId]);

    return (
      <button
        type="button"
        disabled={disabled}
        onClick={onClick}
        className="flex w-full items-center gap-3 rounded px-2 py-1.5 text-sm hover:bg-accent disabled:opacity-50"
      >
        <UserAvatar userId={userId} className="h-8 w-8" />
        <span className="flex-1 truncate text-left">{name}</span>
        <span
          className={
            picked
              ? 'flex h-5 w-5 items-center justify-center rounded bg-primary text-primary-foreground'
              : 'h-5 w-5 rounded border border-border'
          }
        >
          {picked && <Check className="h-3.5 w-3.5" />}
        </span>
      </button>
    );
  }
);

type TGroupDmDialogProps = TDialogBaseProps & {
  // set when adding to a group that already exists
  channelId?: number;
  memberIds?: number[];
};

// discord's new group: tick up to nine friends. the same list adds friends to an existing group,
// counting the people already in it towards the limit
const GroupDmDialog = memo(
  ({ isOpen, close, channelId, memberIds }: TGroupDmDialogProps) => {
    const { t } = useTranslation('dialogs');
    const { friends } = useFriendLists();
    const users = useUsers();
    const [query, setQuery] = useState('');
    const [picked, setPicked] = useState<number[]>([]);
    const [saving, setSaving] = useState(false);

    const isAdding = channelId !== undefined;
    const existing = useMemo(() => memberIds ?? [], [memberIds]);
    const count = 1 + existing.length + picked.length;

    const options = useMemo(() => {
      const search = query.trim().toLowerCase();

      return users.filter(
        (user) =>
          friends.includes(user.id) &&
          !existing.includes(user.id) &&
          user.name.toLowerCase().includes(search)
      );
    }, [existing, friends, query, users]);

    const canSave = !saving && picked.length >= (isAdding ? 1 : 2);

    const onQueryChange = useCallback(
      (event: React.ChangeEvent<HTMLInputElement>) =>
        setQuery(event.target.value),
      []
    );

    const onToggle = useCallback((userId: number) => {
      setPicked((current) =>
        current.includes(userId)
          ? current.filter((id) => id !== userId)
          : [...current, userId]
      );
    }, []);

    const onSave = useCallback(async () => {
      setSaving(true);

      try {
        const trpc = getTRPCClient();

        if (channelId !== undefined) {
          await trpc.dms.addGroupMembers.mutate({
            channelId,
            userIds: picked
          });
          await loadDirectMessages();
        } else {
          const result = await trpc.dms.createGroup.mutate({ userIds: picked });

          await loadDirectMessages();
          setSelectedDmChannelId(result.channelId);
        }

        close();
      } catch (error) {
        toast.error(getTrpcError(error, t('failedSaveGroup')));
      } finally {
        setSaving(false);
      }
    }, [channelId, close, picked, t]);

    let emptyMessage: string | undefined;

    if (options.length === 0) {
      emptyMessage = query ? t('noFriendsByName') : t('groupNeedsFriends');
    }

    return (
      <Dialog open={isOpen}>
        <DialogContent onInteractOutside={close} close={close}>
          <DialogHeader>
            <DialogTitle>
              {isAdding ? t('addToGroupTitle') : t('newGroupTitle')}
            </DialogTitle>
            <DialogDescription>
              {t('groupMemberCount', { count, max: GROUP_DM_MAX_MEMBERS })}
            </DialogDescription>
          </DialogHeader>

          <AutoFocus>
            <Input
              value={query}
              onChange={onQueryChange}
              placeholder={t('searchFriends')}
            />
          </AutoFocus>

          <div className="max-h-80 overflow-y-auto">
            {emptyMessage && (
              <p className="px-2 py-4 text-sm text-muted-foreground">
                {emptyMessage}
              </p>
            )}
            {options.map((user) => {
              const isPicked = picked.includes(user.id);

              return (
                <FriendOption
                  key={user.id}
                  userId={user.id}
                  name={user.name}
                  picked={isPicked}
                  disabled={!isPicked && count >= GROUP_DM_MAX_MEMBERS}
                  onToggle={onToggle}
                />
              );
            })}
          </div>

          <DialogFooter className="gap-2">
            <Button variant="ghost" onClick={close}>
              {t('cancel')}
            </Button>
            <Button onClick={onSave} disabled={!canSave}>
              {isAdding ? t('addToGroupBtn') : t('createGroupBtn')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    );
  }
);

export { GroupDmDialog };
