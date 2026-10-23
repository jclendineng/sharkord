import { hotkeys } from '@/lib/hotkeys/dispatcher';
import type { THotkeyAction, THotkeyPhase } from '@/lib/hotkeys/types';
import {
  useCallback,
  useEffect,
  useEffectEvent,
  useMemo,
  useSyncExternalStore
} from 'react';

const useHotkeyState = () =>
  useSyncExternalStore(hotkeys.subscribe, hotkeys.getState);

const useHotkeyAction = (
  { id, label, mode }: THotkeyAction,
  handler: (phase: THotkeyPhase) => void,
  enabled = true
) => {
  // always the latest handler, without registering again when it changes
  const onHotkey = useEffectEvent(handler);

  useEffect(() => {
    if (!enabled) {
      return;
    }

    return hotkeys.registerAction({ id, label, mode }, (phase) =>
      onHotkey(phase)
    );
  }, [id, label, mode, enabled]);
};

const useHotkeyBinding = (actionId: string) => {
  const { bindings, errors } = useHotkeyState();

  const combo = useMemo(() => {
    const bind = bindings.find((candidate) => candidate.actionId === actionId);

    return bind ? bind.combo : undefined;
  }, [bindings, actionId]);

  const setCombo = useCallback(
    (next: string) => hotkeys.setBinding(actionId, next),
    [actionId]
  );

  const clear = useCallback(() => {
    hotkeys.setBinding(actionId);
  }, [actionId]);

  return { combo, error: errors[actionId], setCombo, clear };
};

export { useHotkeyAction, useHotkeyBinding, useHotkeyState };
