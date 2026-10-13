import { t } from '../../utils/trpc';
import { registerDeviceRoute } from './register-device';
import { unregisterDeviceRoute } from './unregister-device';

export const notificationsRouter = t.router({
  registerDevice: registerDeviceRoute,
  unregisterDevice: unregisterDeviceRoute
});
