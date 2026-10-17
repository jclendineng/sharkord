import { getDefaultRole, getRole, getUserRoleIds } from '../db/queries/roles';
import { getSettings } from '../db/queries/server';
import { assignRole, removeRole } from './user-roles';

// a reaction to the rules message gives the onboarding role, once. taking the reaction back
// leaves it, accepting the rules is not undone by tidying up a reaction
const grantOnboardingRole = async (userId: number, messageId: number) => {
  const {
    onboardingMessageId,
    onboardingRoleId,
    onboardingRemovesDefaultRole
  } = await getSettings();

  if (onboardingMessageId !== messageId || !onboardingRoleId) {
    return;
  }

  const [role, roleIds] = await Promise.all([
    getRole(onboardingRoleId),
    getUserRoleIds(userId)
  ]);

  if (!role) {
    return;
  }

  // someone given the role before the default one was set to go, by hand or by an earlier
  // reaction, still loses the default role on reacting now
  if (!roleIds.includes(role.id)) {
    try {
      await assignRole(userId, role);
    } catch {
      // a second reaction landing at the same moment already gave it
      return;
    }
  }

  if (!onboardingRemovesDefaultRole) {
    return;
  }

  const defaultRole = await getDefaultRole();

  if (!defaultRole || !roleIds.includes(defaultRole.id)) {
    return;
  }

  const joinedDefaultRole = await getRole(defaultRole.id);

  if (joinedDefaultRole) {
    try {
      await removeRole(userId, joinedDefaultRole);
    } catch {
      // already gone, taken by an admin or a reaction at the same moment
    }
  }
};

export { grantOnboardingRole };
