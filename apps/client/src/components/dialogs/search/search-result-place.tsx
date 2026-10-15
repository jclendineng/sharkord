import { useConversationTitle } from '@/features/server/hooks';
import { AtSign, Hash } from 'lucide-react';
import { memo } from 'react';

type TSearchResultPlaceProps = {
  channelId: number;
  channelName: string;
  isDm: boolean;
};

// where a result was posted: #channel, or for a direct message the person or group, since its
// channel is only named after the two ids in it
const SearchResultPlace = memo(
  ({ channelId, channelName, isDm }: TSearchResultPlaceProps) => {
    const conversationTitle = useConversationTitle(channelId);

    const Icon = isDm ? AtSign : Hash;
    const name = isDm ? (conversationTitle ?? channelName) : channelName;

    return (
      <span className="inline-flex min-w-0 max-w-full items-center gap-1">
        <Icon className="h-3 w-3" />
        <span className="truncate wrap-anywhere">{name}</span>
      </span>
    );
  }
);

export { SearchResultPlace };
