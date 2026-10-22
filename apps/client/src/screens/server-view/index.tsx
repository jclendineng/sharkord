import { AppBanner } from '@/components/app-banner';
import { LeftSidebar } from '@/components/left-sidebar';
import { ModViewSheet } from '@/components/mod-view-sheet';
import { Protect } from '@/components/protect';
import { RightSidebar } from '@/components/right-sidebar';
import { ThreadSidebar } from '@/components/thread-sidebar';
import { TopBar } from '@/components/top-bar';
import { VoiceChatSidebar } from '@/components/voice-chat-sidebar';
import { VoiceProvider } from '@/components/voice-provider';
import { setMobileDrawer } from '@/features/app/actions';
import {
  useMobileDrawer,
  useSelectedDmChannelId,
  useThreadSidebar
} from '@/features/app/hooks';
import { setDmsOpen } from '@/features/server/actions';
import { setSelectedChannelId } from '@/features/server/channels/actions';
import { useSelectedChannelId } from '@/features/server/channels/hooks';
import { useDmsOpen, usePublicServerSettings } from '@/features/server/hooks';
import {
  getLocalStorageItemBool,
  LocalStorageKey,
  setLocalStorageItemBool
} from '@/helpers/storage';
import { useSwipeGestures } from '@/hooks/use-swipe-gestures';
import { cn } from '@/lib/utils';
import { MobileDrawer } from '@/types';
import { TestId, USER_MODERATION_PERMISSIONS } from '@sharkord/shared';
import { memo, useCallback, useEffect, useRef, useState } from 'react';
import { ContentWrapper } from './content-wrapper';
import { PreventBrowser } from './prevent-browser';

const ServerView = memo(() => {
  const mobileDrawer = useMobileDrawer();
  const isMobileMenuOpen = mobileDrawer === MobileDrawer.CHANNELS;
  const isMobileUsersOpen = mobileDrawer === MobileDrawer.MEMBERS;
  const [isDesktopRightSidebarOpen, setIsDesktopRightSidebarOpen] = useState(
    getLocalStorageItemBool(LocalStorageKey.RIGHT_SIDEBAR_STATE, true)
  );
  const dmsOpen = useDmsOpen();
  const selectedDmChannelId = useSelectedDmChannelId();
  const publicSettings = usePublicServerSettings();
  const previousServerChannelIdRef = useRef<number | undefined>(undefined);
  const { isOpen: isThreadSidebarOpen } = useThreadSidebar();
  const selectedChannelId = useSelectedChannelId();

  let hasOpenChannel = !!selectedChannelId;

  if (dmsOpen) {
    hasOpenChannel = !!selectedDmChannelId;
  }

  const handleDesktopRightSidebarToggle = useCallback(() => {
    setIsDesktopRightSidebarOpen((prev) => !prev);
    setLocalStorageItemBool(
      LocalStorageKey.RIGHT_SIDEBAR_STATE,
      !isDesktopRightSidebarOpen
    );
  }, [isDesktopRightSidebarOpen]);

  const handleSwipeRight = useCallback(() => {
    if (mobileDrawer) {
      setMobileDrawer(undefined);
      return;
    }

    setMobileDrawer(MobileDrawer.CHANNELS);
  }, [mobileDrawer]);

  const handleSwipeLeft = useCallback(() => {
    if (mobileDrawer) {
      setMobileDrawer(undefined);

      return;
    }

    setMobileDrawer(MobileDrawer.MEMBERS);
  }, [mobileDrawer]);

  const closeMobileDrawer = useCallback(() => {
    setMobileDrawer(undefined);
  }, []);

  const swipeHandlers = useSwipeGestures({
    onSwipeRight: handleSwipeRight,
    onSwipeLeft: handleSwipeLeft
  });

  // a phone has no home screen worth landing on, so with nothing open, such as after signing in
  // or leaving a call, the channel list opens to pick from
  useEffect(() => {
    const phoneQuery = window.matchMedia('(max-width: 767px)');

    if (!hasOpenChannel && phoneQuery.matches) {
      setMobileDrawer(MobileDrawer.CHANNELS);
    }
  }, [hasOpenChannel]);

  // ios safari scrolls the page up to keep a field above the keyboard and can leave it there
  // once the keyboard closes, though this layout never scrolls, cutting off its top and leaving
  // a gap at the bottom. focus moving to another field keeps the keyboard up, so that is left be
  useEffect(() => {
    const onFocusOut = () => {
      setTimeout(() => {
        const active = document.activeElement;
        const isTyping =
          active instanceof HTMLInputElement ||
          active instanceof HTMLTextAreaElement ||
          (active instanceof HTMLElement && active.isContentEditable);

        if (!isTyping && window.scrollY !== 0) {
          window.scrollTo(0, 0);
        }
      }, 100);
    };

    document.addEventListener('focusout', onFocusOut);

    return () => {
      document.removeEventListener('focusout', onFocusOut);
    };
  }, []);

  useEffect(() => {
    if (publicSettings?.directMessagesEnabled === false && dmsOpen) {
      setDmsOpen(false);

      if (previousServerChannelIdRef.current) {
        setSelectedChannelId(previousServerChannelIdRef.current);
      }
    }
  }, [publicSettings?.directMessagesEnabled, dmsOpen]);

  return (
    <VoiceProvider>
      <div
        data-testid={TestId.SERVER_VIEW}
        className="flex h-dvh flex-col bg-background text-foreground dark"
        {...swipeHandlers}
      >
        <AppBanner />
        <TopBar
          onToggleRightSidebar={handleDesktopRightSidebarToggle}
          isOpen={isDesktopRightSidebarOpen}
        />
        <div className="relative flex min-h-0 flex-1 overflow-hidden">
          <PreventBrowser />

          {isMobileMenuOpen && (
            <div
              className="md:hidden fixed inset-0 bg-black/50 z-30"
              onClick={closeMobileDrawer}
            />
          )}

          {isMobileUsersOpen && (
            <div
              className="lg:hidden fixed inset-0 bg-black/50 z-30"
              onClick={closeMobileDrawer}
            />
          )}

          <LeftSidebar
            className={cn(
              'md:relative md:flex fixed inset-0 left-0 h-full z-40 md:z-0 transition-transform duration-300 ease-in-out',
              isMobileMenuOpen
                ? 'translate-x-0'
                : '-translate-x-full md:translate-x-0'
            )}
          />

          <ContentWrapper
            isDmMode={dmsOpen}
            selectedDmChannelId={selectedDmChannelId}
          />

          <VoiceChatSidebar />

          <ThreadSidebar isOpen={isThreadSidebarOpen} />

          <RightSidebar
            className={cn(
              'fixed top-0 bottom-0 right-0 h-full z-40',
              'lg:relative lg:z-0',
              isMobileUsersOpen
                ? 'translate-x-0 lg:translate-x-0'
                : 'translate-x-full lg:translate-x-0'
            )}
            isOpen={isMobileUsersOpen || isDesktopRightSidebarOpen}
          />

          <Protect permission={USER_MODERATION_PERMISSIONS}>
            <ModViewSheet />
          </Protect>
        </div>
      </div>
    </VoiceProvider>
  );
});

export { ServerView };
