import { useUserById } from '@/features/server/users/hooks';
import { getFileUrl } from '@/helpers/get-file-url';
import { getInitialsFromName } from '@/helpers/get-initials-from-name';
import { getRenderedUsername } from '@/helpers/get-rendered-username';
import { cn } from '@/lib/utils';
import { getAvatarGradient, UserStatus } from '@sharkord/shared';
import { Avatar, AvatarFallback, AvatarImage } from '@sharkord/ui';
import { memo, useCallback, useMemo } from 'react';
import { UserPopover } from '../user-popover';
import { UserStatusBadge } from '../user-status';

type TUserAvatarProps = {
  userId: number | null;
  className?: string;
  showUserPopover?: boolean;
  showStatusBadge?: boolean;
  onClick?: () => void;
};

const UserAvatar = memo(
  ({
    userId,
    className,
    showUserPopover = false,
    showStatusBadge = true,
    onClick
  }: TUserAvatarProps) => {
    const user = useUserById(userId);
    const profileColor = user?.profileColor;

    const fallbackStyle = useMemo(() => {
      const { from, to } = getAvatarGradient(userId ?? 0, profileColor);

      return { backgroundImage: `linear-gradient(135deg, ${from}, ${to})` };
    }, [userId, profileColor]);

    // an avatar that does something on a click is a button to a keyboard and a screen
    // reader as well, not only to a pointer
    const onKeyDown = useCallback(
      (e: React.KeyboardEvent) => {
        if (!onClick) return;
        if (e.key !== 'Enter' && e.key !== ' ') return;

        e.preventDefault();
        onClick();
      },
      [onClick]
    );

    if (!user) return null;

    const content = (
      <div
        className="relative size-fit"
        onClick={onClick}
        onKeyDown={onKeyDown}
        role={onClick ? 'button' : undefined}
        tabIndex={onClick ? 0 : undefined}
      >
        <Avatar className={cn('size-8 bg-muted', className)}>
          <AvatarImage
            src={getFileUrl(user.avatar)}
            key={user.avatarId}
            className="object-cover"
          />
          <AvatarFallback
            className="text-xs font-semibold text-white"
            style={fallbackStyle}
          >
            {getInitialsFromName(getRenderedUsername(user))}
          </AvatarFallback>
        </Avatar>
        {showStatusBadge && (
          <UserStatusBadge
            status={user.status || UserStatus.OFFLINE}
            className="absolute bottom-0 right-0"
          />
        )}
      </div>
    );

    if (!showUserPopover || userId === null) return content;

    return <UserPopover userId={userId}>{content}</UserPopover>;
  }
);

export { UserAvatar };
