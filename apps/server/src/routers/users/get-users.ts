import { USER_MODERATION_PERMISSIONS } from '@sharkord/shared';
import { getUsers } from '../../db/queries/users';
import { clearFields } from '../../helpers/clear-fields';
import { needsAnyPermission } from '../../helpers/needs-any-permission';
import { protectedProcedure } from '../../utils/trpc';

const getUsersRoute = protectedProcedure.query(async ({ ctx }) => {
  await needsAnyPermission(ctx, USER_MODERATION_PERMISSIONS);

  const users = await getUsers();

  return clearFields(users, [
    'identity',
    'password',
    'tokenVersion',
    'oidcSub',
    'oidcIssuer'
  ]);
});

export { getUsersRoute };
