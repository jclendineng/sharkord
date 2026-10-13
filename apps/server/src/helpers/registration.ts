import { config } from '../config';
import { updateSettings } from '../db/mutations/server';

// whether someone without an invite may sign up: the settings screen switch, unless config.ini
// has locked the server to invites
const isRegistrationOpen = (allowNewUsers: boolean): boolean =>
  allowNewUsers && !config.registration.inviteOnly;

// with invite only on in config.ini the stored switch is turned off too, so the settings
// screens show what the server actually does. it stays off if the lock is lifted later
const applyInviteOnly = async () => {
  if (!config.registration.inviteOnly) {
    return;
  }

  await updateSettings({ allowNewUsers: false });
};

export { applyInviteOnly, isRegistrationOpen };
