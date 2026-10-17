import type { ServerScreen } from '@/components/server-screens/screens';
import type { TGenericObject } from '@sharkord/shared';
import { setMobileDrawer } from '../app/actions';
import { store } from '../store';
import { serverScreenSliceActions } from './slice';

export const openServerScreen = (
  serverScreen: ServerScreen,
  props?: TGenericObject
) => {
  // a settings screen opened from the channel list would otherwise sit under it on a phone
  setMobileDrawer(undefined);
  store.dispatch(
    serverScreenSliceActions.openServerScreen({ serverScreen, props })
  );
};

export const closeServerScreens = () => {
  store.dispatch(serverScreenSliceActions.closeServerScreens());
};

export const resetServerScreens = () => {
  store.dispatch(serverScreenSliceActions.resetServerScreens());
};
