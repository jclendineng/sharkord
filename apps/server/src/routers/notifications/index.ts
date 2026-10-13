import { t } from '../../utils/trpc';
import { getChannelSettingsRoute } from './get-channel-settings';
import { registerDeviceRoute } from './register-device';
import { setChannelSettingRoute } from './set-channel-setting';
import { unregisterDeviceRoute } from './unregister-device';

export const notificationsRouter = t.router({
  registerDevice: registerDeviceRoute,
  unregisterDevice: unregisterDeviceRoute,
  getChannelSettings: getChannelSettingsRoute,
  setChannelSetting: setChannelSettingRoute
});
