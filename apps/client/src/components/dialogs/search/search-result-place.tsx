import { UserAvatar } from '@/components/user-avatar';
import { useConversation, useConversationTitle } from '@/features/server/hooks';
import { Hash, Users } from 'lucide-react';
import { memo } from 'react';

type TSearchResultPlaceProps = {
  channelId: number;
  channelName: string;
  isDm: boolean;
};

type TPlaceIconProps = {
  channelId: number;
  isDm: boolean;
};

// discord's: a channel's #, the person's avatar for a direct message, a group's picture
const PlaceIcon = memo(({ channelId, isDm }: TPlaceIconProps) => {
  const conversation = useConversation(channelId);

  if (!isDm) {
    return <Hash className="h-3 w-3" />;
  }

  if (!conversation || conversation.group) {
    return <Users className="h-3 w-3" />;
  }

  return (
    <UserAvatar
      userId={conversation.userId}
      className="h-4 w-4"
      showStatusBadge={false}
    />
  );
});

// where a result was posted: #channel, or for a direct message the person or group, since its
// channel is only named after the two ids in it
const SearchResultPlace = memo(
  ({ channelId, channelName, isDm }: TSearchResultPlaceProps) => {
    const conversationTitle = useConversationTitle(channelId);

    const name = isDm ? (conversationTitle ?? channelName) : channelName;

    return (
      <span className="inline-flex min-w-0 max-w-full items-center gap-1">
        <PlaceIcon channelId={channelId} isDm={isDm} />
        <span className="truncate wrap-anywhere">{name}</span>
      </span>
    );
  }
);

export { SearchResultPlace };
