import { closeDialogs } from '@/features/dialogs/actions';
import { useDialogInfo } from '@/features/dialogs/hooks';
import {
  createElement,
  memo,
  type ComponentProps,
  type ComponentType
} from 'react';
import { AssignRoleDialog } from './assign-role';
import { ConfirmActionDialog } from './confirm-action';
import { CreateCategoryDialog } from './create-category';
import { CreateChannelDialog } from './create-channel';
import { CreateInviteDialog } from './create-invite-dialog';
import { CreatePollDialog } from './create-poll';
import { DeleteUserDialog } from './delete-user';
import { Dialog } from './dialogs';
import { FriendsDialog } from './friends';
import { GroupDmDialog } from './group-dm';
import { PluginInstallConfirmDialog } from './plugin-install-confirm';
import { RulesSetupDialog } from './rules-setup';
import { SearchDialog } from './search';
import { ServerPasswordDialog } from './server-password';
import { SoundsDialog } from './sounds';
import { TextInputDialog } from './text-input';
import type { TDialogBaseProps } from './types';
import { VoiceDebugDialog } from './voice-debug';
import { WelcomeProfileSetupDialog } from './welcome-profile-setup';

const DialogsMap = {
  [Dialog.CONFIRM_ACTION]: ConfirmActionDialog,
  [Dialog.CREATE_CHANNEL]: CreateChannelDialog,
  [Dialog.TEXT_INPUT]: TextInputDialog,
  [Dialog.SERVER_PASSWORD]: ServerPasswordDialog,
  [Dialog.SOUNDS]: SoundsDialog,
  [Dialog.ASSIGN_ROLE]: AssignRoleDialog,
  [Dialog.CREATE_INVITE]: CreateInviteDialog,
  [Dialog.CREATE_CATEGORY]: CreateCategoryDialog,
  [Dialog.CREATE_POLL]: CreatePollDialog,
  [Dialog.PLUGIN_INSTALL_CONFIRM]: PluginInstallConfirmDialog,
  [Dialog.DELETE_USER]: DeleteUserDialog,
  [Dialog.SEARCH]: SearchDialog,
  [Dialog.WELCOME_PROFILE_SETUP]: WelcomeProfileSetupDialog,
  [Dialog.VOICE_DEBUG]: VoiceDebugDialog,
  [Dialog.GROUP_DM]: GroupDmDialog,
  [Dialog.FRIENDS]: FriendsDialog,
  [Dialog.RULES_SETUP]: RulesSetupDialog
} satisfies Record<Dialog, ComponentType<never>>;

// what a dialog takes on top of being open and closing, which the provider hands it
export type TDialogProps<D extends Dialog> = Omit<
  ComponentProps<(typeof DialogsMap)[D]>,
  keyof TDialogBaseProps
>;

// the store holds the props of whichever dialog is open, checked against that dialog where
// openDialog was called
type TOpenDialogComponent = ComponentType<
  TDialogBaseProps & Record<string, unknown>
>;

const DialogsProvider = memo(() => {
  const { isOpen, openDialog, props, closing } = useDialogInfo();

  if (!openDialog) return null;

  const realIsOpen = isOpen && !closing;
  const component = DialogsMap[openDialog] as TOpenDialogComponent;

  return createElement(component, {
    ...props,
    isOpen: realIsOpen,
    close: closeDialogs
  });
});

export { DialogsProvider };
