import {
  clearVoiceDebugEvents,
  collectVoiceDebugSnapshot,
  getVoiceDebugEvents,
  type TVoiceDebugEvent,
  type TVoiceDebugSnapshot
} from '@/helpers/voice-debug';
import {
  Button,
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger
} from '@sharkord/ui';
import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import type { TDialogBaseProps } from '../types';
import { computeRates, formatTime } from './helpers';
import { OverviewTab } from './overview-tab';
import {
  ConsumersTab,
  EventsTab,
  ProducersTab,
  RawTab,
  TransportsTab
} from './tabs';

const REFRESH_MS = 1000;

// the dialog is translated, the stats in it are not: they are webrtc's own names, which the
// copied report is read against
const VoiceDebugDialog = memo(({ isOpen, close }: TDialogBaseProps) => {
  const { t } = useTranslation('dialogs');
  const [snapshot, setSnapshot] = useState<TVoiceDebugSnapshot | undefined>(
    undefined
  );
  const [events, setEvents] = useState<TVoiceDebugEvent[]>([]);
  const [rates, setRates] = useState<Record<string, number>>({});
  const [paused, setPaused] = useState(false);

  const previousSnapshot = useRef<TVoiceDebugSnapshot | undefined>(undefined);

  useEffect(() => {
    if (!isOpen || paused) return;

    let cancelled = false;

    const collect = async () => {
      const next = await collectVoiceDebugSnapshot();

      if (cancelled) return;

      setRates(computeRates(previousSnapshot.current, next));
      previousSnapshot.current = next;
      setSnapshot(next);
      setEvents([...getVoiceDebugEvents()]);
    };

    collect();

    const interval = setInterval(collect, REFRESH_MS);

    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, [isOpen, paused]);

  const json = useMemo(
    () => JSON.stringify({ snapshot, events }, null, 2),
    [snapshot, events]
  );

  const connectionEvents = useMemo(
    () =>
      events
        .filter(
          (event) => event.category === 'ws' || event.category === 'error'
        )
        .slice(-5),
    [events]
  );

  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(json);
      toast.success(t('voiceDebugCopied'));
    } catch (error) {
      toast.error(t('voiceDebugCopyFailed', { error: String(error) }));
    }
  }, [json, t]);

  const handleTogglePause = useCallback(() => {
    setPaused((current) => !current);
  }, []);

  const handleClearEvents = useCallback(() => {
    clearVoiceDebugEvents();
    setEvents([]);
  }, []);

  return (
    <Dialog open={isOpen} onOpenChange={close}>
      <DialogContent className="flex h-[90vh] w-[95vw] max-w-[95vw] min-w-[95vw] flex-col">
        <DialogHeader>
          <DialogTitle className="flex flex-wrap items-center gap-3 pr-6">
            <span>{t('voiceDebugTitle')}</span>
            <span className="font-mono text-xs font-normal text-muted-foreground">
              {snapshot
                ? formatTime(snapshot.capturedAt)
                : t('voiceDebugCollecting')}
              {paused && ` · ${t('voiceDebugPaused')}`}
            </span>
            <span className="ml-auto flex flex-wrap gap-2">
              <Button size="sm" variant="outline" onClick={handleTogglePause}>
                {paused ? t('voiceDebugResume') : t('voiceDebugPause')}
              </Button>
              <Button size="sm" variant="outline" onClick={handleClearEvents}>
                {t('voiceDebugClearEvents')}
              </Button>
              <Button size="sm" onClick={handleCopy}>
                {t('voiceDebugCopyReport')}
              </Button>
            </span>
          </DialogTitle>
        </DialogHeader>

        <Tabs
          defaultValue="overview"
          className="flex min-h-0 min-w-0 flex-1 flex-col"
        >
          <TabsList className="w-fit max-w-full flex-wrap">
            <TabsTrigger value="overview">
              {t('voiceDebugOverview')}
            </TabsTrigger>
            <TabsTrigger value="transports">
              {t('voiceDebugTransports')}
            </TabsTrigger>
            <TabsTrigger value="producers">
              {t('voiceDebugProducers')}
            </TabsTrigger>
            <TabsTrigger value="consumers">
              {t('voiceDebugConsumers')}
            </TabsTrigger>
            <TabsTrigger value="events">
              {t('voiceDebugEvents', { count: events.length })}
            </TabsTrigger>
            <TabsTrigger value="raw">{t('voiceDebugRaw')}</TabsTrigger>
          </TabsList>

          <div className="min-h-0 min-w-0 flex-1 overflow-y-auto pr-2">
            {!snapshot && (
              <p className="font-mono text-[11px] text-muted-foreground">
                {t('voiceDebugCollecting')}
              </p>
            )}
            {!!snapshot && (
              <>
                <TabsContent value="overview">
                  <OverviewTab
                    snapshot={snapshot}
                    rates={rates}
                    connectionEvents={connectionEvents}
                  />
                </TabsContent>
                <TabsContent value="transports">
                  <TransportsTab snapshot={snapshot} />
                </TabsContent>
                <TabsContent value="producers">
                  <ProducersTab snapshot={snapshot} />
                </TabsContent>
                <TabsContent value="consumers">
                  <ConsumersTab snapshot={snapshot} />
                </TabsContent>
                <TabsContent value="events">
                  <EventsTab events={events} />
                </TabsContent>
                <TabsContent value="raw">
                  <RawTab json={json} />
                </TabsContent>
              </>
            )}
          </div>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
});

VoiceDebugDialog.displayName = 'VoiceDebugDialog';

export { VoiceDebugDialog };
