import { OWNER_ROLE_ID, type TRole } from '@sharkord/shared';
import { getTopRolePosition, getUserRoleIds } from '../db/queries/roles';
import { invariant } from '../utils/invariant';

// only roles below the actor's own highest one, so nobody hands out a rank equal to or above
// their own. the owner can assign any role, the owner's role itself is guarded by
// assertCanModifyOwnerRole. removing needs no such check: a member holding a role ranks at
// least as high as it, so assertCanActOnUser already turns that down
const assertCanAssignRole = async (actorUserId: number, role: TRole) => {
  const actorRoleIds = await getUserRoleIds(actorUserId);

  if (actorRoleIds.includes(OWNER_ROLE_ID)) return;

  const actorPosition = await getTopRolePosition(actorUserId);
  // a lower position ranks higher, and the default role ranks below every other
  const rolePosition = role.isDefault ? Infinity : role.position;

  invariant((actorPosition ?? Infinity) < rolePosition, {
    code: 'FORBIDDEN',
    message: 'You can only assign roles below your highest role.'
  });
};

export { assertCanAssignRole };
