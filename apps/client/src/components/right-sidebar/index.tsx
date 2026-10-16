import { PluginSlotRenderer } from '@/components/plugin-slot-renderer';
import { ResizableSidebar } from '@/components/resizable-sidebar';
import { UserAvatar } from '@/components/user-avatar';
import {
  useChannelById,
  useSelectedChannelId
} from '@/features/server/channels/hooks';
import { useUsers } from '@/features/server/users/hooks';
import { LocalStorageKey } from '@/helpers/storage';
import { getTRPCClient } from '@/lib/trpc';
import { cn } from '@/lib/utils';
import {
  DELETED_USER_IDENTITY_AND_NAME,
  PluginSlot,
  TestId
} from '@sharkord/shared';
import { memo, useCallback, useEffect, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { UserPopover } from '../user-popover';

const MAX_USERS_TO_SHOW = 100;
const MIN_WIDTH = 180;
const MAX_WIDTH = 360;
const DEFAULT_WIDTH = 240; // w-60 = 240px

type TUserProps = {
  userId: number;
  name: string;
  banned: boolean;
};

const User = memo(({ userId, name, banned }: TUserProps) => {
  const pluginProps = useMemo(() => ({ userId }), [userId]);

  return (
    <UserPopover userId={userId}>
      <div
        data-testid={TestId.MEMBER_ITEM}
        className="flex items-center gap-3 rounded px-2 py-1.5 hover:bg-accent select-none min-w-0"
      >
        <UserAvatar userId={userId} className="h-8 w-8 shrink-0" />
        <span
          className={cn(
            'text-sm text-foreground truncate',
            banned && 'line-through text-muted-foreground'
          )}
        >
          {name}
        </span>

        <PluginSlotRenderer
          slotId={PluginSlot.MEMBER_LIST_ITEM}
          props={pluginProps}
        />
      </div>
    </UserPopover>
  );
});

type TRightSidebarProps = {
  className?: string;
  isOpen?: boolean;
};

const RightSidebar = memo(
  ({ className, isOpen = true }: TRightSidebarProps) => {
    const { t } = useTranslation('sidebar');
    const users = useUsers();
    const selectedChannelId = useSelectedChannelId();
    const selectedChannel = useChannelById(selectedChannelId ?? 0);
    const [channelMemberIds, setChannelMemberIds] = useState<Set<number>>();
    const [showsEveryone, setShowsEveryone] = useState(false);

    // a public channel is open to everyone, so only a private one has a narrower list
    const isPrivateChannel =
      !!selectedChannel?.private && !selectedChannel.isDm;
    const filtersToChannel = isPrivateChannel && !showsEveryone;

    useEffect(() => {
      if (!filtersToChannel || selectedChannelId === undefined) {
        setChannelMemberIds(undefined);
        return;
      }

      let isCurrent = true;

      const load = async () => {
        try {
          const trpc = getTRPCClient();
          const memberIds = await trpc.channels.getMembers.query({
            channelId: selectedChannelId
          });

          if (isCurrent) setChannelMemberIds(new Set(memberIds));
        } catch {
          // the full list stays up, which is what this showed before
          if (isCurrent) setChannelMemberIds(undefined);
        }
      };

      load();

      return () => {
        isCurrent = false;
      };
    }, [filtersToChannel, selectedChannelId, users.length]);

    const toggleShowsEveryone = useCallback(() => {
      setShowsEveryone((previous) => !previous);
    }, []);

    const { usersToShow, usersCount } = useMemo(() => {
      const filtered = users.filter(
        (user) =>
          user.name !== DELETED_USER_IDENTITY_AND_NAME &&
          (!channelMemberIds || channelMemberIds.has(user.id))
      );

      return {
        usersToShow: filtered.slice(0, MAX_USERS_TO_SHOW),
        usersCount: filtered.length
      };
    }, [users, channelMemberIds]);

    const hasHiddenUsers = usersCount > MAX_USERS_TO_SHOW;

    return (
      <ResizableSidebar
        storageKey={LocalStorageKey.RIGHT_SIDEBAR_WIDTH}
        minWidth={MIN_WIDTH}
        maxWidth={MAX_WIDTH}
        defaultWidth={DEFAULT_WIDTH}
        edge="left"
        isOpen={isOpen}
        className={cn('h-full', className)}
      >
        <div className="flex h-12 items-center justify-between gap-2 border-b border-border px-4">
          <h3 className="text-sm font-semibold text-foreground">
            {t('membersHeader', { count: usersCount })}
          </h3>
          {isPrivateChannel && (
            <button
              type="button"
              onClick={toggleShowsEveryone}
              className="text-xs text-muted-foreground hover:text-foreground"
            >
              {showsEveryone ? t('membersThisChannel') : t('membersEveryone')}
            </button>
          )}
        </div>
        <div className="flex-1 overflow-y-auto p-2">
          <div className="space-y-1">
            {usersToShow.map((user) => (
              <User
                key={user.id}
                userId={user.id}
                name={user.name}
                banned={user.banned}
              />
            ))}
            {hasHiddenUsers && (
              <div className="text-sm text-muted-foreground px-2 py-1.5">
                +{usersCount - MAX_USERS_TO_SHOW} more...
              </div>
            )}
          </div>
        </div>
      </ResizableSidebar>
    );
  }
);

export { RightSidebar };
