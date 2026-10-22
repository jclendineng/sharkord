import { OWNER_ROLE_ID } from '@sharkord/shared';
import { getSignupInviteRoleId } from '../db/queries/invites';
import { getDefaultRole, getRole, getUserRoleIds } from '../db/queries/roles';
import { getSettings } from '../db/queries/server';
import { assignRole, removeRole } from './user-roles';

// the role the member's invite carries, held back at sign up until the rules are accepted so an
// invite cannot let anyone past them. given with the onboarding role the first time, never again
const grantSignupInviteRole = async (userId: number, roleIds: number[]) => {
  const inviteRoleId = await getSignupInviteRoleId(userId);

  if (!inviteRoleId || roleIds.includes(inviteRoleId)) {
    return;
  }

  const inviteRole = await getRole(inviteRoleId);

  if (!inviteRole || inviteRole.isDefault || inviteRole.id === OWNER_ROLE_ID) {
    return;
  }

  try {
    await assignRole(userId, inviteRole);
  } catch {
    // given in the meantime, by hand or by another reaction
  }
};

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

    await grantSignupInviteRole(userId, roleIds);
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
