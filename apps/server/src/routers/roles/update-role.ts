import {
  HEX_COLOR_REGEX,
  Permission,
  STORAGE_MAX_QUOTA_PER_USER,
  STORAGE_MIN_QUOTA_PER_USER
} from '@sharkord/shared';
import { z } from 'zod';
import { assertCanModifyOwnerRole } from '../../helpers/assert-can-modify-owner-role';
import { loadRole, updateRole } from '../../helpers/roles';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

const updateRoleRoute = protectedProcedure
  .input(
    z.object({
      roleId: z.number().min(1),
      name: z.string().min(1).max(26),
      color: z.string().regex(HEX_COLOR_REGEX, 'Invalid hex color'),
      permissions: z.enum(Permission).array(),
      storageQuotaOverrideEnabled: z.boolean(),
      storageSpaceQuota: z
        .number()
        .min(STORAGE_MIN_QUOTA_PER_USER)
        .max(STORAGE_MAX_QUOTA_PER_USER)
    })
  )
  .mutation(async ({ ctx, input }) => {
    await ctx.needsPermission(Permission.MANAGE_ROLES);

    const role = await loadRole(input.roleId);

    // the owner role is granted by id and the ui trusts its name, so only an owner edits it
    await assertCanModifyOwnerRole(ctx.userId, role.id, 'edit');

    const addedPermissions = input.permissions.filter(
      (permission) => !role.permissions.includes(permission)
    );
    const removedPermissions = role.permissions.filter(
      (permission) => !input.permissions.includes(permission)
    );

    invariant(await ctx.hasPermission(addedPermissions), {
      code: 'FORBIDDEN',
      message: 'You cannot grant permissions that you do not have.'
    });

    // a permission the caller lacks may stay on the role while they rename it, but taking it
    // away would let a role manager strip a more privileged role
    invariant(await ctx.hasPermission(removedPermissions), {
      code: 'FORBIDDEN',
      message: 'You cannot remove permissions that you do not have.'
    });

    await updateRole(role, input, ctx.user.id);
  });

export { updateRoleRoute };
