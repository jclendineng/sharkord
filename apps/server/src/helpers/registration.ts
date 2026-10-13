import { config } from '../config';

// whether someone without an invite may sign up: the settings screen switch, unless config.ini
// has locked the server to invites
const isRegistrationOpen = (allowNewUsers: boolean): boolean =>
  allowNewUsers && !config.registration.inviteOnly;

export { isRegistrationOpen };
