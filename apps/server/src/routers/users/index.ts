import { t } from '../../utils/trpc';
import { addRoleRoute } from './add-role';
import { banRoute } from './ban';
import { changeAvatarRoute } from './change-avatar';
import { changeBannerRoute } from './change-banner';
import { confirmTwoFactorRoute } from './confirm-two-factor';
import { createPasswordResetRoute } from './create-password-reset';
import { deleteOwnAccountRoute } from './delete-own-account';
import { deleteUserRoute } from './delete-user';
import { disableTwoFactorRoute } from './disable-two-factor';
import {
  onUserCreateRoute,
  onUserDeleteRoute,
  onUserJoinRoute,
  onUserLeaveRoute,
  onUserUpdateRoute
} from './events';
import { getNoteRoute } from './get-note';
import { getTwoFactorRoute } from './get-two-factor';
import { getUserInfoRoute } from './get-user-info';
import { getUsersRoute } from './get-users';
import { kickRoute } from './kick';
import { removeRoleRoute } from './remove-role';
import { startTwoFactorRoute } from './start-two-factor';
import { unbanRoute } from './unban';
import { updatePasswordRoute } from './update-password';
import { updateUserRoute } from './update-user';

import { getPresenceRoute } from './get-presence';
import { getPrivacyRoute } from './get-privacy';
import { setNoteRoute } from './set-note';
import { setPresenceRoute } from './set-presence';
import { updatePrivacyRoute } from './update-privacy';

export const usersRouter = t.router({
  changeAvatar: changeAvatarRoute,
  changeBanner: changeBannerRoute,
  addRole: addRoleRoute,
  removeRole: removeRoleRoute,
  update: updateUserRoute,
  updatePassword: updatePasswordRoute,
  getPrivacy: getPrivacyRoute,
  getPresence: getPresenceRoute,
  setPresence: setPresenceRoute,
  updatePrivacy: updatePrivacyRoute,
  getInfo: getUserInfoRoute,
  getNote: getNoteRoute,
  setNote: setNoteRoute,
  getAll: getUsersRoute,
  kick: kickRoute,
  ban: banRoute,
  unban: unbanRoute,
  delete: deleteUserRoute,
  deleteOwn: deleteOwnAccountRoute,
  createPasswordReset: createPasswordResetRoute,
  getTwoFactor: getTwoFactorRoute,
  startTwoFactor: startTwoFactorRoute,
  confirmTwoFactor: confirmTwoFactorRoute,
  disableTwoFactor: disableTwoFactorRoute,
  onJoin: onUserJoinRoute,
  onLeave: onUserLeaveRoute,
  onUpdate: onUserUpdateRoute,
  onCreate: onUserCreateRoute,
  onDelete: onUserDeleteRoute
});
