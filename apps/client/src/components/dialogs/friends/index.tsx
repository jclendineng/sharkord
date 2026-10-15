import { changeFriendship } from '@/features/server/dms/actions';
import { useFriendLists } from '@/features/server/dms/hooks';
import { useServerName } from '@/features/server/hooks';
import { useOwnUserId, useUsers } from '@/features/server/users/hooks';
import { DELETED_USER_IDENTITY_AND_NAME } from '@sharkord/shared';
import {
  AutoFocus,
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  Input
} from '@sharkord/ui';
import { memo, useCallback, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import type { TDialogBaseProps } from '../types';
import { FriendRow } from './friend-row';

type TSectionProps = {
  title: string;
  userIds: number[];
  onOpenedDm: () => void;
};

const Section = memo(({ title, userIds, onOpenedDm }: TSectionProps) => {
  if (userIds.length === 0) {
    return null;
  }

  return (
    <div>
      <p className="px-2 pb-1 pt-3 text-xs font-semibold uppercase text-muted-foreground">
        {title} ({userIds.length})
      </p>
      {userIds.map((userId) => (
        <FriendRow key={userId} userId={userId} onOpenedDm={onOpenedDm} />
      ))}
    </div>
  );
});

// friends for one server: there is no central directory, everyone you could add is already here.
// add by username, then requests waiting on you, the ones you sent, your friends and everyone else
const FriendsDialog = memo(({ isOpen, close }: TDialogBaseProps) => {
  const { t } = useTranslation('dialogs');
  const lists = useFriendLists();
  const users = useUsers();
  const ownUserId = useOwnUserId();
  const serverName = useServerName();
  const [username, setUsername] = useState('');
  const [result, setResult] = useState<{ ok: boolean; text: string }>();
  const [query, setQuery] = useState('');

  const sections = useMemo(() => {
    const search = query.trim().toLowerCase();
    const linked = new Set([
      ...lists.friends,
      ...lists.incoming,
      ...lists.outgoing
    ]);

    const visible = users.filter(
      (user) =>
        user.id !== ownUserId &&
        !user.banned &&
        user.name !== DELETED_USER_IDENTITY_AND_NAME &&
        user.name.toLowerCase().includes(search)
    );

    const idsIn = (ids: number[]) =>
      visible.filter((user) => ids.includes(user.id)).map((user) => user.id);

    return {
      incoming: idsIn(lists.incoming),
      outgoing: idsIn(lists.outgoing),
      friends: idsIn(lists.friends),
      others: visible
        .filter((user) => !linked.has(user.id))
        .map((user) => user.id)
    };
  }, [lists, ownUserId, query, users]);

  const onUsernameChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setUsername(event.target.value);
      setResult(undefined);
    },
    []
  );

  const onQueryChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) =>
      setQuery(event.target.value),
    []
  );

  const onSendRequest = useCallback(async () => {
    const wanted = username.trim().toLowerCase();
    const user = users.find(
      (candidate) => candidate.name.toLowerCase() === wanted
    );

    if (!user || user.id === ownUserId) {
      setResult({
        ok: false,
        text: t('nobodyByName', { name: username.trim(), server: serverName })
      });

      return;
    }

    const sent = await changeFriendship('request', user.id);

    if (sent) {
      setResult({
        ok: true,
        text: t('friendRequestSent', { name: user.name })
      });
      setUsername('');
    }
  }, [ownUserId, serverName, t, username, users]);

  return (
    <Dialog open={isOpen}>
      <DialogContent onInteractOutside={close} close={close}>
        <DialogHeader>
          <DialogTitle>{t('friendsTitle')}</DialogTitle>
          <DialogDescription>{t('addByUsernameMsg')}</DialogDescription>
        </DialogHeader>

        <div className="flex gap-2">
          <AutoFocus>
            <Input
              value={username}
              onChange={onUsernameChange}
              onEnter={onSendRequest}
              placeholder={t('enterUsername')}
            />
          </AutoFocus>
          <Button onClick={onSendRequest} disabled={!username.trim()}>
            {t('sendFriendRequest')}
          </Button>
        </div>
        {result && (
          <p
            className={
              result.ok ? 'text-sm text-green-500' : 'text-sm text-destructive'
            }
          >
            {result.text}
          </p>
        )}

        <Input
          value={query}
          onChange={onQueryChange}
          placeholder={t('searchPeople')}
        />

        <div className="max-h-96 overflow-y-auto">
          <Section
            title={t('friendRequests')}
            userIds={sections.incoming}
            onOpenedDm={close}
          />
          <Section
            title={t('sentRequests')}
            userIds={sections.outgoing}
            onOpenedDm={close}
          />
          <Section
            title={t('friendsSection')}
            userIds={sections.friends}
            onOpenedDm={close}
          />
          <Section
            title={t('peopleOnServer', { server: serverName })}
            userIds={sections.others}
            onOpenedDm={close}
          />
        </div>
      </DialogContent>
    </Dialog>
  );
});

export { FriendsDialog };
