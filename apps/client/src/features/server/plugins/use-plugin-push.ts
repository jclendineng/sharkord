import { useEffect, useEffectEvent } from 'react';
import { usePluginId } from './plugin-id-context';
import { onPluginPush, type TPushHandler } from './push-registry';

const usePluginPush = (handler: TPushHandler) => {
  const pluginId = usePluginId();
  // always the latest handler, without resubscribing when it changes
  const onPush = useEffectEvent(handler);

  useEffect(() => {
    if (!pluginId) return;

    return onPluginPush(pluginId, (data) => onPush(data));
  }, [pluginId]);
};

export { usePluginPush };
