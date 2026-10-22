import { OWNER_ROLE_ID } from '@sharkord/shared';
import { getTopRolePosition, getUserRoleIds } from '../db/queries/roles';
import { invariant } from '../utils/invariant';

// moderation follows the role order: a member can only be acted on by someone whose highest
// role sits above theirs, so a moderator can't ban an admin. the owner can act on anyone and
// only the owner can act on the owner
const assertCanActOnUser = async (
  actorUserId: number,
  targetUserId: number
) => {
  const [actorRoleIds, targetRoleIds] = await Promise.all([
    getUserRoleIds(actorUserId),
    getUserRoleIds(targetUserId)
  ]);

  if (actorRoleIds.includes(OWNER_ROLE_ID)) return;

  invariant(!targetRoleIds.includes(OWNER_ROLE_ID), {
    code: 'FORBIDDEN',
    message: 'Only users with the owner role can act on the server owner.'
  });

  const [actorPosition, targetPosition] = await Promise.all([
    getTopRolePosition(actorUserId),
    getTopRolePosition(targetUserId)
  ]);

  // a lower position ranks higher, and a member with only the default role ranks lowest
  invariant((actorPosition ?? Infinity) < (targetPosition ?? Infinity), {
    code: 'FORBIDDEN',
    message: 'You can only act on members whose highest role is below yours.'
  });
};

export { assertCanActOnUser };
