import type { Permission } from '@sharkord/shared';
import { invariant } from '../utils/invariant';
import type { Context } from '../utils/trpc';

// the context's needsPermission wants every permission in a list, this wants any one of them
const needsAnyPermission = async (ctx: Context, permissions: Permission[]) => {
  const results = await Promise.all(
    permissions.map((permission) => ctx.hasPermission(permission))
  );

  invariant(results.some(Boolean), {
    code: 'FORBIDDEN',
    message: 'Insufficient permissions'
  });
};

export { needsAnyPermission };
