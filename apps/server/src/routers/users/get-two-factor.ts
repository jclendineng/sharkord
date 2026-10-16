import { isTwoFactorEnabled } from '../../helpers/two-factor';
import { protectedProcedure } from '../../utils/trpc';

const getTwoFactorRoute = protectedProcedure.query(async ({ ctx }) => ({
  enabled: await isTwoFactorEnabled(ctx.userId)
}));

export { getTwoFactorRoute };
