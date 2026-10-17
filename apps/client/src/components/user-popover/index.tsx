import { PluginSlotRenderer } from '@/components/plugin-slot-renderer';
import { setModViewOpen, setSelectedDmChannelId } from '@/features/app/actions';
import { setDmsOpen } from '@/features/server/actions';
import {
  changeFriendship,
  type TFriendshipAction
} from '@/features/server/dms/actions';
import { useFriendStatus } from '@/features/server/dms/hooks';
import { usePublicServerSettings, useUserRoles } from '@/features/server/hooks';
import { useIsOwnUser, useUserById } from '@/features/server/users/hooks';
import { getFileUrl } from '@/helpers/get-file-url';
import { getRenderedUsername } from '@/helpers/get-rendered-username';
import { useDateLocale } from '@/hooks/use-date-locale';
import { getTRPCClient } from '@/lib/trpc';
import {
  DELETED_USER_IDENTITY_AND_NAME,
  Permission,
  PluginSlot,
  TestId,
  UserStatus,
  getTrpcError
} from '@sharkord/shared';
import {
  IconButton,
  Popover,
  PopoverContent,
  PopoverTrigger
} from '@sharkord/ui';
import { format } from 'date-fns';
import {
  MessageSquare,
  ShieldCheck,
  Trash,
  UserCheck,
  UserCog,
  UserMinus,
  UserPlus,
  UserX,
  type LucideIcon
} from 'lucide-react';
import { memo, useCallback, useMemo, useSyncExternalStore } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import { Protect } from '../protect';
import { RoleBadge } from '../role-badge';
import { UserAvatar } from '../user-avatar';
import { UserStatusBadge } from '../user-status';
import { UserNote } from './user-note';

// a phone has no room beside a name for the card, so there it opens below, where it can slide
// sideways to fit on the screen
const narrowScreenQuery = window.matchMedia('(max-width: 639px)');

const subscribeNarrowScreen = (onChange: () => void) => {
  narrowScreenQuery.addEventListener('change', onChange);

  return () => {
    narrowScreenQuery.removeEventListener('change', onChange);
  };
};

const getIsNarrowScreen = () => narrowScreenQuery.matches;

type TUserPopoverProps = {
  userId: number;
  children: React.ReactNode;
};

const UserPopover = memo(({ userId, children }: TUserPopoverProps) => {
  const { t } = useTranslation();
  const dateLocale = useDateLocale();
  const user = useUserById(userId);
  const roles = useUserRoles(userId);
  const settings = usePublicServerSettings();
  const isNarrowScreen = useSyncExternalStore(
    subscribeNarrowScreen,
    getIsNarrowScreen
  );
  const isOwnUser = useIsOwnUser(userId);
  const friendStatus = useFriendStatus(userId);

  const pluginProps = useMemo(() => ({ userId }), [userId]);

  const onDirectMessageClick = useCallback(async () => {
    const trpc = getTRPCClient();

    try {
      const result = await trpc.dms.open.mutate({ userId });

      setDmsOpen(true);
      setSelectedDmChannelId(result.channelId);
    } catch (error) {
      toast.error(getTrpcError(error, t('couldNotOpenDM')));
    }
  }, [userId, t]);

  // one button that does the next thing: ask, accept, take back the request, or unfriend
  const friendButton = useMemo((): {
    icon: LucideIcon;
    title: string;
    action: TFriendshipAction;
  } => {
    if (friendStatus === 'friend') {
      return { icon: UserMinus, title: t('removeFriend'), action: 'remove' };
    }

    if (friendStatus === 'incoming') {
      return { icon: UserCheck, title: t('acceptFriend'), action: 'accept' };
    }

    if (friendStatus === 'outgoing') {
      return { icon: UserX, title: t('cancelFriendRequest'), action: 'remove' };
    }

    return { icon: UserPlus, title: t('addFriend'), action: 'request' };
  }, [friendStatus, t]);

  const onFriendClick = useCallback(() => {
    changeFriendship(friendButton.action, userId);
  }, [friendButton, userId]);

  const onModerateClick = useCallback(() => {
    setModViewOpen(true, userId);
  }, [userId]);

  if (!user) return <>{children}</>;

  const isDeleted = user.name === DELETED_USER_IDENTITY_AND_NAME;
  const showDmButton =
    settings?.directMessagesEnabled && !isDeleted && !isOwnUser;
  const showFriendButton = !isDeleted && !isOwnUser && !user.banned;

  return (
    <Popover>
      <PopoverTrigger asChild>{children}</PopoverTrigger>
      <PopoverContent
        className="w-80 p-0"
        align="start"
        side={isNarrowScreen ? 'bottom' : 'right'}
        collisionPadding={8}
      >
        <div className="relative">
          {user.banned && (
            <div className="absolute right-2 top-2 bg-red-500 text-white text-xs px-2 py-1 rounded-md flex items-center gap-1">
              <ShieldCheck className="h-3 w-3" />
              {t('bannedBadge')}
            </div>
          )}
          {isDeleted && (
            <div className="absolute right-2 top-2 bg-gray-600 text-white text-xs px-2 py-1 rounded-md flex items-center gap-1">
              <Trash className="h-3 w-3" />
              {t('deletedBadge')}
            </div>
          )}
          {user.banner ? (
            <div
              className="h-24 w-full rounded-t-md bg-cover bg-center bg-no-repeat"
              style={{
                backgroundImage: `url("${getFileUrl(user.banner)}")`
              }}
            />
          ) : (
            <div
              className="h-24 w-full rounded-t-md"
              style={{
                background: user.profileColor || '#5865f2'
              }}
            />
          )}
          <div className="absolute left-4 top-16">
            <UserAvatar
              userId={user.id}
              className="h-16 w-16 border-4 border-card"
              showStatusBadge={false}
            />
          </div>
        </div>

        <div className="px-4 pt-12 pb-4">
          <div className="mb-3">
            <span className="text-lg font-semibold text-foreground truncate mb-1">
              {getRenderedUsername(user)}
            </span>
            <div className="flex items-center gap-2">
              <div className="flex items-center gap-2">
                <UserStatusBadge
                  status={user.status || UserStatus.OFFLINE}
                  className="h-3 w-3"
                />
                <span className="text-xs text-muted-foreground capitalize">
                  {user.status || UserStatus.OFFLINE}
                </span>
              </div>
            </div>
          </div>

          {roles.length > 0 && (
            <div className="flex flex-wrap gap-1.5 mb-3">
              {roles.map((role) => (
                <RoleBadge key={role.id} role={role} />
              ))}
            </div>
          )}

          {user.bio && (
            <div className="mt-3">
              <p className="text-sm text-foreground leading-relaxed">
                {user.bio}
              </p>
            </div>
          )}
          {!isOwnUser && !isDeleted && <UserNote userId={user.id} />}
          <div className="flex justify-between items-center mt-4 pt-3 border-t border-border">
            <p className="text-xs text-muted-foreground">
              {t('memberSince', {
                date: format(new Date(user.createdAt), 'PP', {
                  locale: dateLocale
                })
              })}
            </p>

            <div className="flex gap-2 items-center">
              <PluginSlotRenderer
                slotId={PluginSlot.USER_POPOVER}
                props={pluginProps}
              />

              {showFriendButton && (
                <IconButton
                  icon={friendButton.icon}
                  variant="ghost"
                  size="sm"
                  title={friendButton.title}
                  onClick={onFriendClick}
                />
              )}

              {showDmButton && (
                <IconButton
                  data-testid={TestId.USER_POPOVER_DM}
                  icon={MessageSquare}
                  variant="ghost"
                  size="sm"
                  title={t('directMessage')}
                  onClick={onDirectMessageClick}
                />
              )}

              {
                <Protect permission={Permission.MANAGE_USERS}>
                  <IconButton
                    data-testid={TestId.USER_POPOVER_MODERATE}
                    icon={UserCog}
                    variant="ghost"
                    size="sm"
                    title={t('moderationView')}
                    onClick={onModerateClick}
                  />
                </Protect>
              }
            </div>
          </div>
        </div>
      </PopoverContent>
    </Popover>
  );
});

UserPopover.displayName = 'UserPopover';

export { UserPopover };
