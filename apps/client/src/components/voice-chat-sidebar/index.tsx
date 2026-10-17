import { TextChannel } from '@/components/channel-view/text';
import { ResizableSidebar } from '@/components/resizable-sidebar';
import { closeVoiceChatSidebar } from '@/features/app/actions';
import { useVoiceChatSidebar } from '@/features/app/hooks';
import { LocalStorageKey } from '@/helpers/storage';
import { memo } from 'react';

// below desktop width there is no room beside the chat, so an open panel covers it instead of
// staying hidden
const FULL_SCREEN_BELOW_DESKTOP =
  'max-lg:fixed max-lg:inset-0 max-lg:z-40 max-lg:w-full! max-lg:border-0';

const MIN_WIDTH = 360;
const MAX_WIDTH = 600;
const DEFAULT_WIDTH = 384;

const VoiceChatSidebar = memo(() => {
  const { isOpen, channelId } = useVoiceChatSidebar();

  if (!channelId) {
    return null;
  }

  return (
    <ResizableSidebar
      storageKey={LocalStorageKey.VOICE_CHAT_SIDEBAR_WIDTH}
      minWidth={MIN_WIDTH}
      maxWidth={MAX_WIDTH}
      defaultWidth={DEFAULT_WIDTH}
      edge="left"
      isOpen={isOpen}
      className={isOpen ? FULL_SCREEN_BELOW_DESKTOP : 'hidden lg:flex'}
    >
      <div className="flex flex-col h-full w-full">
        <div className="flex-1 flex flex-col overflow-hidden">
          <TextChannel channelId={channelId} onClose={closeVoiceChatSidebar} />
        </div>
      </div>
    </ResizableSidebar>
  );
});

export { VoiceChatSidebar };
