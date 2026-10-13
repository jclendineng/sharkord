import { Permission } from '@sharkord/shared';
import { config } from '../../config';
import { getSettings } from '../../db/queries/server';
import { clearFields } from '../../helpers/clear-fields';
import { protectedProcedure } from '../../utils/trpc';

const getSettingsRoute = protectedProcedure.query(async ({ ctx }) => {
  await ctx.needsPermission(Permission.MANAGE_SETTINGS);

  const settings = await getSettings();

  // the join password is returned so the settings form can show what is actually set and let
  // it be cleared. it is stored in plaintext by design and this route needs MANAGE_SETTINGS,
  // so it only ever reaches an admin. the secret token is not the same thing: it is the
  // ownership credential and the jwt signing key, and stays stripped
  // inviteOnly comes from config.ini and overrides allowNewUsers, the form shows it locked
  return {
    ...clearFields(settings, ['secretToken']),
    inviteOnly: config.registration.inviteOnly
  };
});

export { getSettingsRoute };
