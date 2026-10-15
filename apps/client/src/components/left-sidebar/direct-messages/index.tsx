import { Dialog } from '@/components/dialogs/dialogs';
import { setSelectedDmChannelId } from '@/features/app/actions';
import { useSelectedDmChannelId } from '@/features/app/hooks';
import { openDialog } from '@/features/dialogs/actions';
import { loadDirectMessages } from '@/features/server/dms/actions';
import { useDirectMessages, useFriendLists } from '@/features/server/dms/hooks';
import { useOwnUserId, useUsers } from '@/features/server/users/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { DELETED_USER_IDENTITY_AND_NAME, getTrpcError } from '@sharkord/shared';
import { IconButton } from '@sharkord/ui';
import { UserPlus, Users } from 'lucide-react';
import { memo, useCallback, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import { DirectMessageItem } from './direct-message-item';
import { SearchUserDropdown } from './search-user-dropdown';

const DirectMessages = memo(() => {
  const { t } = useTranslation('sidebar');
  const [query, setQuery] = useState('');
  const conversations = useDirectMessages();
  const { incoming } = useFriendLists();
  const users = useUsers();
  const ownUserId = useOwnUserId();
  const selectedDmChannelId = useSelectedDmChannelId();

  const usersToStartDm = useMemo(() => {
    const directMessageUserIds = new Set(
      conversations.filter((dm) => !dm.group).map((dm) => dm.userId)
    );

    return users.filter(
      (user) =>
        user.id !== ownUserId &&
        !user.banned &&
        user.name !== DELETED_USER_IDENTITY_AND_NAME &&
        !directMessageUserIds.has(user.id) &&
        user.name.toLowerCase().includes(query.trim().toLowerCase())
    );
  }, [conversations, ownUserId, query, users]);

  const onStartDm = useCallback(
    async (userId: number) => {
      try {
        const trpc = getTRPCClient();
        const result = await trpc.dms.open.mutate({ userId });

        setSelectedDmChannelId(result.channelId);
        await loadDirectMessages();
      } catch (error) {
        toast.error(getTrpcError(error, t('couldNotOpenDM')));
      }
    },
    [t]
  );

  const onAddFriendsClick = useCallback(() => {
    openDialog(Dialog.FRIENDS);
  }, []);

  const onNewGroupClick = useCallback(() => {
    openDialog(Dialog.GROUP_DM);
  }, []);

  return (
    <div className="flex-1 overflow-y-auto p-2">
      <div className="mb-1 flex items-center justify-between px-2 py-1">
        <span className="text-xs font-semibold text-muted-foreground">
          {t('directMessages')}
        </span>
        <div className="flex items-center">
          <div className="relative">
            <IconButton
              variant="ghost"
              size="sm"
              icon={UserPlus}
              title={t('addFriends')}
              onClick={onAddFriendsClick}
            />
            {incoming.length > 0 && (
              <span className="pointer-events-none absolute right-0 top-0 h-2 w-2 rounded-full bg-destructive" />
            )}
          </div>
          <IconButton
            variant="ghost"
            size="sm"
            icon={Users}
            title={t('newGroup')}
            onClick={onNewGroupClick}
          />
          <SearchUserDropdown
            query={query}
            setQuery={setQuery}
            usersToStartDm={usersToStartDm}
            onStartDm={onStartDm}
          />
        </div>
      </div>

      <div className="space-y-0.5">
        {conversations.map((dm) => (
          <DirectMessageItem
            key={dm.channelId}
            dm={dm}
            selected={selectedDmChannelId === dm.channelId}
          />
        ))}
        {conversations.length === 0 && (
          <div className="px-2 py-4 text-xs text-muted-foreground">
            {t('noDMsYet')}
          </div>
        )}
      </div>
    </div>
  );
});

export { DirectMessages };
