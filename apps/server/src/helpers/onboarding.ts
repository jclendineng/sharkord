import { getRole, getUserRoleIds } from '../db/queries/roles';
import { getSettings } from '../db/queries/server';
import { assignRole } from './user-roles';

// a reaction to the rules message gives the onboarding role, once. taking the reaction back
// leaves it, accepting the rules is not undone by tidying up a reaction
const grantOnboardingRole = async (userId: number, messageId: number) => {
  const { onboardingMessageId, onboardingRoleId } = await getSettings();

  if (onboardingMessageId !== messageId || !onboardingRoleId) {
    return;
  }

  const [role, roleIds] = await Promise.all([
    getRole(onboardingRoleId),
    getUserRoleIds(userId)
  ]);

  if (!role || roleIds.includes(role.id)) {
    return;
  }

  try {
    await assignRole(userId, role);
  } catch {
    // a second reaction landing at the same moment already gave it
  }
};

export { grantOnboardingRole };
