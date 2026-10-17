import { getPinnedChannelIds } from '../../db/queries/channel-pins';
import { protectedProcedure } from '../../utils/trpc';

const getPinsRoute = protectedProcedure.query(async ({ ctx }) =>
  getPinnedChannelIds(ctx.userId)
);

export { getPinsRoute };
