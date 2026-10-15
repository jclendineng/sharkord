import { UserAvatar } from '@/components/user-avatar';
import { setSelectedDmChannelId } from '@/features/app/actions';
import { setDmsOpen } from '@/features/server/actions';
import { changeFriendship } from '@/features/server/dms/actions';
import { useFriendStatus } from '@/features/server/dms/hooks';
import { useUserById } from '@/features/server/users/hooks';
import { getTRPCClient } from '@/lib/trpc';
import { getTrpcError } from '@sharkord/shared';
import { IconButton } from '@sharkord/ui';
import { Check, MessageSquare, UserMinus, UserPlus, X } from 'lucide-react';
import { memo, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';

type TFriendRowProps = {
  userId: number;
  onOpenedDm: () => void;
};

const FriendRow = memo(({ userId, onOpenedDm }: TFriendRowProps) => {
  const { t } = useTranslation('dialogs');
  const user = useUserById(userId);
  const status = useFriendStatus(userId);

  const onRequest = useCallback(() => {
    changeFriendship('request', userId);
  }, [userId]);

  const onAccept = useCallback(() => {
    changeFriendship('accept', userId);
  }, [userId]);

  const onRemove = useCallback(() => {
    changeFriendship('remove', userId);
  }, [userId]);

  const onMessage = useCallback(async () => {
    try {
      const trpc = getTRPCClient();
      const result = await trpc.dms.open.mutate({ userId });

      setDmsOpen(true);
      setSelectedDmChannelId(result.channelId);
      onOpenedDm();
    } catch (error) {
      toast.error(getTrpcError(error, t('couldNotOpenDM')));
    }
  }, [onOpenedDm, t, userId]);

  if (!user) {
    return null;
  }

  return (
    <div className="flex items-center gap-3 rounded px-2 py-1.5 hover:bg-accent">
      <UserAvatar userId={userId} className="h-8 w-8" />
      <span className="flex-1 truncate text-sm">{user.name}</span>
      {status === 'incoming' && (
        <>
          <IconButton
            variant="ghost"
            size="sm"
            icon={Check}
            title={t('acceptFriend')}
            onClick={onAccept}
          />
          <IconButton
            variant="ghost"
            size="sm"
            icon={X}
            title={t('ignoreFriend')}
            onClick={onRemove}
          />
        </>
      )}
      {status === 'outgoing' && (
        <IconButton
          variant="ghost"
          size="sm"
          icon={X}
          title={t('cancelFriendRequest')}
          onClick={onRemove}
        />
      )}
      {status === 'friend' && (
        <>
          <IconButton
            variant="ghost"
            size="sm"
            icon={MessageSquare}
            title={t('messageFriend')}
            onClick={onMessage}
          />
          <IconButton
            variant="ghost"
            size="sm"
            icon={UserMinus}
            title={t('removeFriend')}
            onClick={onRemove}
          />
        </>
      )}
      {status === 'none' && (
        <IconButton
          variant="ghost"
          size="sm"
          icon={UserPlus}
          title={t('addFriend')}
          onClick={onRequest}
        />
      )}
    </div>
  );
});

export { FriendRow };
