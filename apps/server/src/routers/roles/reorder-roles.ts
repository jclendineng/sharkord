import { ActivityLogType, OWNER_ROLE_ID, Permission } from '@sharkord/shared';
import { and, asc, eq, ne } from 'drizzle-orm';
import { z } from 'zod';
import { db } from '../../db';
import { reorderPositions } from '../../db/mutations/positions';
import { publishRole } from '../../db/publishers';
import { roles } from '../../db/schema';
import { MAX_ROLES } from '../../helpers/roles';
import { enqueueActivityLog } from '../../queues/activity-log';
import { protectedProcedure } from '../../utils/trpc';

// the owner's role stays on top and the default one at the bottom, as discord's @everyone does,
// so only the roles between them move. ids for those two or for no role at all are ignored
const reorderRolesRoute = protectedProcedure
  .input(
    z.object({
      roleIds: z.array(z.number().int().positive()).max(MAX_ROLES)
    })
  )
  .mutation(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.MANAGE_ROLES);

    const movable = await db
      .select({ id: roles.id })
      .from(roles)
      .where(and(ne(roles.id, OWNER_ROLE_ID), eq(roles.isDefault, false)))
      .orderBy(asc(roles.position), asc(roles.id));

    const nextRoleOrder = await reorderPositions(
      roles,
      movable.map(({ id }) => id),
      input.roleIds
    );

    nextRoleOrder.forEach((roleId) => {
      publishRole(roleId, 'update');
    });

    if (nextRoleOrder.length > 0) {
      enqueueActivityLog({
        type: ActivityLogType.REORDERED_ROLES,
        userId: ctx.user.id,
        details: { roleIds: nextRoleOrder }
      });
    }
  });

export { reorderRolesRoute };
